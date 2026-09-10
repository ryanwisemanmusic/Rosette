//! The runtime half of the Windows import-fallback contract.
//!
//! The classification itself is a set of pure facts about the Microsoft x64
//! ABI and lives in `pkg/dll/win32/` -- what convention a name returns, what
//! that convention's refusal value is, and which library is part of the
//! Windows surface at all. Those are things a reader should be able to check
//! without a running guest, so they are a package.
//!
//! What is left here is the part a package may not hold: a mutable record of
//! what one run actually did. The static classification can only say which
//! names are *eligible* for a fallback -- for a large PE that is hundreds of
//! names, most of which are never called. This records the ones that were.

const std = @import("std");

const return_contract = @import("dll_win32_return_contract");
const library_inventory = @import("dll_win32_library_inventory");

pub const ReturnConvention = return_contract.ReturnConvention;
pub const Outcome = return_contract.Outcome;
pub const Fallback = return_contract.Fallback;
pub const returnConvention = return_contract.returnConvention;
pub const fallbackFor = return_contract.fallbackFor;
pub const advice = return_contract.advice;
pub const isComponentObjectName = return_contract.isComponentObjectName;

pub const Subsystem = library_inventory.Subsystem;
pub const subsystemFor = library_inventory.subsystemFor;
pub const isWindowsSurface = library_inventory.isWindowsSurface;
pub const isDegradedImport = library_inventory.isDegradedImport;

/// The capability one *import* belongs to.
///
/// A library is not always one capability: ADVAPI32 hosts both the registry
/// and the security surface, and reporting a `RegOpenKeyExW` fallback under
/// "security and services" sends a reader to the wrong question. Where the
/// name identifies its capability unambiguously it wins over the library it
/// was imported from; otherwise the library answers.
///
/// The name's capability is read off its return convention rather than from a
/// second copy of the name-shape rules, so the two can never disagree about
/// what `RegOpenKeyExW` is.
pub fn subsystemForImport(dll_name: []const u8, function_name: []const u8) Subsystem {
    switch (returnConvention(dll_name, function_name)) {
        .lstatus => return .configuration_store,
        .winsock_status => return .networking,
        // Returning an HRESULT is not the same as being a COM API:
        // `SHGetKnownFolderPath` returns one and is a shell path routine.
        // Only the COM spelling re-homes an import away from its library.
        .hresult => if (return_contract.isComponentObjectName(function_name)) return .component_object,
        else => {},
    }
    return library_inventory.subsystemFor(dll_name);
}

/// A bounded record of the fallbacks a run actually took.
///
/// The static import classification can only say which names are *eligible*
/// for a fallback — for a large PE that is hundreds of names, most of which
/// are never called.  This records the ones that were, so a report names the
/// handful that a run actually depends on instead of the whole inventory.
pub const Ledger = struct {
    pub const capacity: usize = 96;
    pub const name_capacity: usize = 64;
    pub const dll_capacity: usize = 32;

    pub const Entry = struct {
        used: bool = false,
        hazard: bool = false,
        /// Which Windows capability this import belongs to.  A report that
        /// groups by filename tells you "GDI32.dll"; grouping by capability
        /// tells you whether the run can proceed without it.
        subsystem: Subsystem = .unrecognized,
        name_buffer: [name_capacity]u8 = [_]u8{0} ** name_capacity,
        name_length: usize = 0,
        dll_buffer: [dll_capacity]u8 = [_]u8{0} ** dll_capacity,
        dll_length: usize = 0,
        calls: u64 = 0,
        first_step: u64 = 0,
        first_caller_rip: u64 = 0,
        /// The first two Microsoft x64 integer arguments as they were at the
        /// first observation.  For an import whose stub cannot be judged from
        /// its name alone -- a comparison, a search, a handle lookup -- these
        /// are the operands to go and look at in the guest's memory.
        first_arg0: u64 = 0,
        first_arg1: u64 = 0,
        convention: ReturnConvention = .zero_count,
        outcome: Outcome = .refused,
        value: u64 = 0,
        /// Set when the entry has appeared since the last report, so a
        /// checkpoint can print only what is new.
        unreported: bool = false,

        pub fn name(self: *const Entry) []const u8 {
            return self.name_buffer[0..self.name_length];
        }

        pub fn dll(self: *const Entry) []const u8 {
            return self.dll_buffer[0..self.dll_length];
        }
    };

    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    /// Fallbacks taken by names that did not fit the table.  Kept so a
    /// truncated report says so rather than looking complete.
    overflow_calls: u64 = 0,
    overflow_names: u64 = 0,
    total_calls: u64 = 0,
    unreported_count: usize = 0,

    fn store(destination: []u8, source: []const u8) usize {
        const length = @min(destination.len, source.len);
        @memcpy(destination[0..length], source[0..length]);
        return length;
    }

    /// Record one fallback.  Returns true when this is the first time the
    /// name has been seen, which is the only moment worth logging eagerly.
    pub fn note(
        self: *Ledger,
        dll_name: []const u8,
        name: []const u8,
        fallback: Fallback,
        step: u64,
        caller_rip: u64,
        arg0: u64,
        arg1: u64,
    ) bool {
        self.total_calls +|= 1;
        for (self.entries[0..self.count]) |*entry| {
            if (!std.mem.eql(u8, entry.name(), name[0..@min(name.len, name_capacity)])) continue;
            entry.calls +|= 1;
            return false;
        }
        if (self.count == capacity) {
            self.overflow_calls +|= 1;
            self.overflow_names +|= 1;
            return false;
        }
        var entry = Entry{
            .used = true,
            .calls = 1,
            .first_step = step,
            .first_caller_rip = caller_rip,
            .first_arg0 = arg0,
            .first_arg1 = arg1,
            .convention = fallback.convention,
            .outcome = fallback.outcome,
            .value = fallback.value,
            .hazard = fallback.hazard,
            .subsystem = subsystemForImport(dll_name, name),
            .unreported = true,
        };
        entry.name_length = store(&entry.name_buffer, name);
        entry.dll_length = store(&entry.dll_buffer, dll_name);
        self.entries[self.count] = entry;
        self.count += 1;
        self.unreported_count += 1;
        return true;
    }

    pub fn isEmpty(self: *const Ledger) bool {
        return self.count == 0;
    }

    /// Fallbacks whose returned value is something a guest can act on — the
    /// subset worth reading first when a run misbehaves.
    pub fn refusedCount(self: *const Ledger) usize {
        var total: usize = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.outcome == .refused) total += 1;
        }
        return total;
    }

    /// Fallbacks that answered rather than refused, where the answer is one
    /// the call had not earned.  These are the ones a report must never
    /// collapse away.
    pub fn hazardCount(self: *const Ledger) usize {
        var total: usize = 0;
        for (self.entries[0..self.count]) |entry| {
            if (entry.hazard) total += 1;
        }
        return total;
    }

    /// True when this entry is worth a line of its own; everything else
    /// collapses into a single summary line.
    pub fn entryNeedsDetail(entry: Entry) bool {
        return entry.outcome == .refused or entry.hazard;
    }

    pub fn markReported(self: *Ledger) void {
        for (self.entries[0..self.count]) |*entry| entry.unreported = false;
        self.unreported_count = 0;
    }

    /// Indices ordered by call count, most-called first, so a bounded report
    /// shows the fallbacks a run leans on rather than the first ones it hit.
    pub fn rankedInto(self: *const Ledger, out: []usize) usize {
        const total = @min(out.len, self.count);
        var used: usize = 0;
        var taken = [_]bool{false} ** capacity;
        while (used < total) : (used += 1) {
            var best: ?usize = null;
            for (self.entries[0..self.count], 0..) |entry, index| {
                if (taken[index]) continue;
                const better = if (best) |current|
                    entry.calls > self.entries[current].calls
                else
                    true;
                if (better) best = index;
            }
            const chosen = best orelse break;
            taken[chosen] = true;
            out[used] = chosen;
        }
        return used;
    }
};

test "the ledger keeps first-observation evidence and ranks by call count" {
    var ledger = Ledger{};
    try std.testing.expect(ledger.isEmpty());

    const reg = fallbackFor("ADVAPI32.dll", "RegOpenKeyExW");
    try std.testing.expect(ledger.note("ADVAPI32.dll", "RegOpenKeyExW", reg, 100, 0x1400_1000, 0x80000002, 0x1234));
    // A repeat is not a new observation, so nothing needs to be logged again.
    try std.testing.expect(!ledger.note("ADVAPI32.dll", "RegOpenKeyExW", reg, 200, 0x1400_2000, 0, 0));

    const blit = fallbackFor("GDI32.dll", "BitBlt");
    try std.testing.expect(ledger.note("GDI32.dll", "BitBlt", blit, 300, 0x1400_3000, 0, 0));

    try std.testing.expectEqual(@as(usize, 2), ledger.count);
    try std.testing.expectEqual(@as(u64, 3), ledger.total_calls);
    try std.testing.expectEqual(@as(u64, 100), ledger.entries[0].first_step);
    try std.testing.expectEqual(@as(u64, 0x1400_1000), ledger.entries[0].first_caller_rip);
    // The first observation keeps the operands, which is the only place a
    // report can point someone at what the call was actually asked to do.
    try std.testing.expectEqual(@as(u64, 0x80000002), ledger.entries[0].first_arg0);
    try std.testing.expectEqual(@as(u64, 0x1234), ledger.entries[0].first_arg1);
    // ...and the capability it belongs to, so the report can order by what a
    // run actually loses rather than by which filename sorts first.
    // ADVAPI32 hosts both the registry and the security surface, so the name
    // decides which of the two a registry fallback is reported under.
    try std.testing.expectEqual(Subsystem.configuration_store, ledger.entries[0].subsystem);
    try std.testing.expectEqual(Subsystem.legacy_drawing, ledger.entries[1].subsystem);

    var order: [4]usize = undefined;
    try std.testing.expectEqual(@as(usize, 2), ledger.rankedInto(&order));
    try std.testing.expectEqualStrings("RegOpenKeyExW", ledger.entries[order[0]].name());
    try std.testing.expectEqualStrings("BitBlt", ledger.entries[order[1]].name());

    try std.testing.expectEqual(@as(usize, 2), ledger.unreported_count);
    ledger.markReported();
    try std.testing.expectEqual(@as(usize, 0), ledger.unreported_count);
    // Reporting does not forget the entry, so the exit summary is complete.
    try std.testing.expectEqual(@as(usize, 2), ledger.count);
}

test "an import's capability is its name's when the name is unambiguous" {
    // The registry is not the security surface, even though one library
    // exports both.
    try std.testing.expectEqual(
        Subsystem.configuration_store,
        subsystemForImport("ADVAPI32.dll", "RegOpenKeyExW"),
    );
    try std.testing.expectEqual(
        Subsystem.security,
        subsystemForImport("ADVAPI32.dll", "AdjustTokenPrivileges"),
    );
    // A COM name imported from an API set is still COM.
    try std.testing.expectEqual(
        Subsystem.component_object,
        subsystemForImport("api-ms-win-core-winrt-l1-1-0.dll", "RoGetActivationFactory"),
    );
    // ...but a DXGI factory stays with the graphics stack rather than being
    // re-homed to COM for returning an HRESULT.
    try std.testing.expectEqual(
        Subsystem.graphics_stack,
        subsystemForImport("dxgi.dll", "CreateDXGIFactory1"),
    );
    // ...and a shell path routine stays with the shell despite its HRESULT.
    try std.testing.expectEqual(
        Subsystem.shell,
        subsystemForImport("SHELL32.dll", "SHGetKnownFolderPath"),
    );
    try std.testing.expectEqual(Subsystem.networking, subsystemForImport("WSOCK32.dll", "WSAGetLastError"));
    // With no name-shaped answer the library decides.
    try std.testing.expectEqual(Subsystem.legacy_drawing, subsystemForImport("GDI32.dll", "BitBlt"));
    try std.testing.expectEqual(Subsystem.unrecognized, subsystemForImport("mygame.dll", "Something"));
}
