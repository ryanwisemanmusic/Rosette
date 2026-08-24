//! NEAR NULL PREDICTOR — ReleaseFast-friendly near-null receiver signatures.
//!
//! Near-null casualties (a native/guest call dereferencing an address below
//! 0x1000) are rare, but when they fire the causality machinery has to work
//! backwards from the fault. This module works forwards instead: every import
//! dispatch costs one compare (`rdi < NEAR_NULL_LIMIT`), and only near-null
//! receivers record anything. Each distinct (symbol, caller) signature keeps a
//! hit count, the last receiver value, and a bounded chronological ring of the
//! most recent near-null dispatches, so a casualty report can show the
//! behaviors that fed into it.
//!
//! Native member-call casualties (a C++ method run with a null `this`, or on
//! a partially-zeroed object whose member offset became the receiver) never
//! pass through import dispatch, so `note` can never see them. The causality
//! engine records those into the same signature table (`noteNativeReceiver`)
//! before the terminal dump runs, so the dump names the faulting callee and
//! caller with real symbols instead of reading empty.
//!
//! Noise control — a near-null *first argument* is not always a receiver:
//!   * Allocators (`operator new`/`delete`, malloc family) take a size or a
//!     pointer that is legal to delete when null; they never dereference it.
//!   * Syscalls take file descriptors / clock ids / addresses that are legal
//!     to be 0 (`mmap(NULL)` requests any mapping; `pthread_threadid_np(NULL)`
//!     means the calling thread).
//! Those symbols are filtered out entirely so the retained signatures are
//! receiver-shaped: a near-null rdi on a call that will dereference it.
//!
//! The caller is the saved return address at dispatch (the guest call site
//! that entered the import thunk), resolved to a symbol when the address lies
//! inside the image, and always printed as a raw address so unattributable
//! callers (JIT code, dylibs) remain solvable offline.
//!
//! Logging is throttled: one `NEAR NULL PREDICTOR:` line on first sight, then
//! at most a few more per signature (receiver change or doubling thresholds),
//! so a hot near-null loop cannot flood the log. `dump` is called only from
//! the terminal near-null path and from exit diagnostics.

const std = @import("std");
const machoCapturePrint = @import("dyld").event_log.machoCapturePrint;
const symbolication = @import("macho_core").symbolication;
/// Whether `rdi` is a receiver at a given callee is fixed by that callee's
/// declared signature, so it is resolved at build time rather than by walking a
/// string table on the dispatch path. See the package README for why it lives
/// under `pkg/common/` with no route mirror.
const receiver_classification = @import("common_receiver_classification");

/// Receivers below this bound are "near null": dereferencing them faults on
/// the zero page or a tiny tag-like address. Matches the existing 0x1000
/// near-null convention used by the fault classifier and memory views.
pub const NEAR_NULL_LIMIT: u64 = 0x1000;
pub const SIGNATURE_CAPACITY: usize = 32;
pub const RECENT_CAPACITY: usize = 16;
/// Bounded history of object-header clobbers — one event per tracked object
/// whose vptr was observed reading low. Each is a distinct object/address, so
/// the ring is inherently throttled; a hot clobber loop can still only hold 8.
pub const CLOBBER_CAPACITY: usize = 8;
/// Cap per-signature emissions so a recurring signature cannot spam the log.
pub const MAX_EMISSIONS_PER_SIGNATURE: u32 = 4;

/// How a native (non-import) near-null casualty was shaped, recorded by the
/// causality engine at the terminal fault.
pub const NativeReceiverKind = enum {
    /// A C++ member function ran with a null `this` (RDI == 0): the caller
    /// passed a null object, or the object's ownership pointer was cleared.
    null_this,
    /// The base register itself holds a tiny derived value (e.g. 0x48): a
    /// member offset into a partially-zeroed object, the same bypassing
    /// bulk-writer family as `object_header_clobber`.
    derived_member_offset,
};

const Signature = struct {
    valid: bool = false,
    symbol_hash: u64 = 0,
    /// Slice into the guest image's import metadata — stable for the process
    /// lifetime, so no copying is needed.
    symbol: []const u8 = "",
    caller: u64 = 0,
    /// Non-zero for native (non-import) casualties: the faulting callee's
    /// address, resolved to a symbol at print time. Imports leave this zero
    /// and use `symbol` instead.
    callee: u64 = 0,
    receiver: u64 = 0,
    count: u32 = 0,
    emissions: u32 = 0,
    first_seen_step: u64 = 0,
    last_seen_step: u64 = 0,
};

const Recent = struct {
    symbol: []const u8 = "",
    caller: u64 = 0,
    /// Non-zero for native (non-import) casualties — see `Signature.callee`.
    callee: u64 = 0,
    receiver: u64 = 0,
    step: u64 = 0,
};

/// A tracked C++ object whose header was zeroed by a bypassing bulk/native
/// write. The vtable tracker observed the vptr slot reading low and repaired
/// it; every other zeroed pointer slot in the header was *not* repaired and is
/// the predicted near-null: the next native member call that reads one of
/// those fields (e.g. an ownership pointer at +0x8) will carry a null
/// receiver and fault. Fires at the first vptr re-read after the clobber,
/// which precedes the member call that dereferences the field.
const ClobberEvent = struct {
    valid: bool = false,
    object_base: u64 = 0,
    /// Vtable symbol (the object's type), e.g. `__ZTVN2xe6kernel10UserModuleE`.
    type_symbol: []const u8 = "",
    allocation_size: u64 = 0,
    /// Bit i set => the 8-byte slot at object_base + i*8 read as zero.
    zeroed_mask: u64 = 0,
    step: u64 = 0,
    /// Last write the vtable tracker accepted on this slot before the clobber
    /// (usually the constructor) — the clobber happened inside this window.
    last_write_step: u64 = 0,
};

pub const Predictor = struct {
    signatures: [SIGNATURE_CAPACITY]Signature = [_]Signature{.{}} ** SIGNATURE_CAPACITY,
    recent: [RECENT_CAPACITY]Recent = [_]Recent{.{}} ** RECENT_CAPACITY,
    recent_index: usize = 0,
    recent_filled: bool = false,
    near_null_dispatches: u64 = 0,
    benign_skipped: u64 = 0,
    /// Native (non-import) near-null casualties recorded by the causality
    /// engine — the class of fault the import-watching `note` can never see
    /// (a C++ member call on a null `this` or a partially-zeroed object).
    native_receiver_events: u64 = 0,
    distinct_signatures: u32 = 0,
    emissions: u64 = 0,
    clobber: [CLOBBER_CAPACITY]ClobberEvent = [_]ClobberEvent{.{}} ** CLOBBER_CAPACITY,
    clobber_index: usize = 0,
    clobber_filled: bool = false,
    clobber_events: u64 = 0,

    /// Hot path — one compare for the overwhelming majority of dispatches.
    /// Only near-null receivers on receiver-shaped imports resolve the caller
    /// and touch the table.
    pub fn note(self: *Predictor, state: anytype, symbol: []const u8) void {
        const receiver = state.regs.rdi;
        if (receiver >= NEAR_NULL_LIMIT) return;
        self.near_null_dispatches +|= 1;
        // Two different reasons a near-null rdi here predicts nothing: the
        // argument is not a pointer at all, or it is a pointer whose null value
        // is the documented request for a default. Either way retaining it
        // spends a signature slot on a correct call and teaches the reader to
        // distrust the tool.
        const argument_class = receiver_classification.classify(symbol);
        if (!argument_class.predictsCasualty()) {
            self.benign_skipped +|= 1;
            return;
        }

        const caller = importCallerAddress(state);
        const signature = self.findOrInsert(symbol, caller) orelse return;
        self.pushRecent(symbol, caller, 0, receiver, state.executed_steps);

        const step = state.executed_steps;
        const first_sight = signature.count == 0;
        const receiver_changed = signature.receiver != receiver;
        signature.count +|= 1;
        const doubling_threshold = (signature.count & (signature.count - 1)) == 0;
        signature.receiver = receiver;
        signature.last_seen_step = step;
        if (first_sight) signature.first_seen_step = step;

        if (first_sight or
            (receiver_changed and signature.emissions < MAX_EMISSIONS_PER_SIGNATURE) or
            (doubling_threshold and signature.emissions < MAX_EMISSIONS_PER_SIGNATURE))
        {
            signature.emissions +|= 1;
            self.emitSignature(state, signature, first_sight);
        }
    }

    /// Dump every retained signature with readable caller names. Called from
    /// the terminal near-null path (after pinFaultContext) and teardown.
    pub fn dump(self: *Predictor, state: anytype, reason: []const u8) void {
        var retained: usize = 0;
        for (&self.signatures) |*signature| {
            if (!signature.valid) continue;
            retained += 1;
            var caller_buf: [symbolication.LABEL_BUFFER_BYTES]u8 = undefined;
            var callee_buf: [symbolication.LABEL_BUFFER_BYTES]u8 = undefined;
            const caller_label = resolveCallerLabel(state, signature.caller, &caller_buf);
            machoCapturePrint(
                "NEAR NULL PREDICTOR: signature symbol={s} caller={s} receiver=0x{x} count={d} first_seen_step={d} last_seen_step={d} emissions={d}\n",
                .{
                    signatureLabel(state, signature, &callee_buf),
                    caller_label,
                    signature.receiver,
                    signature.count,
                    signature.first_seen_step,
                    signature.last_seen_step,
                    signature.emissions,
                },
            );
        }
        machoCapturePrint(
            "NEAR NULL PREDICTOR: dump reason={s} distinct={d} retained={d} near_null_dispatches={d} benign_skipped={d} native_receivers={d} recent_window={d} emissions={d} abi={s}/{s}; a skipped dispatch is one where the callee's signature says {s} is not a receiver, not one whose fault was ignored\n",
            .{
                reason,
                self.distinct_signatures,
                retained,
                self.near_null_dispatches,
                self.benign_skipped,
                self.native_receiver_events,
                self.recentCount(),
                self.emissions,
                receiver_classification.guest_abi,
                receiver_classification.receiver_register,
                receiver_classification.receiver_register,
            },
        );
    }

    /// The most recent near-null dispatches, oldest first, for correlation.
    pub fn dumpRecent(self: *Predictor, state: anytype) void {
        const count = self.recentCount();
        if (count == 0) return;
        machoCapturePrint(
            "NEAR NULL PREDICTOR: recent near-null dispatches ({d}):\n",
            .{count},
        );
        for (0..count) |ordinal| {
            const recent = self.recentChronological(ordinal) orelse continue;
            var caller_buf: [symbolication.LABEL_BUFFER_BYTES]u8 = undefined;
            var callee_buf: [symbolication.LABEL_BUFFER_BYTES]u8 = undefined;
            const caller_label = resolveCallerLabel(state, recent.caller, &caller_buf);
            const display_symbol = if (recent.callee != 0)
                resolveCallerLabel(state, recent.callee, &callee_buf)
            else
                recent.symbol;
            machoCapturePrint(
                "  [{d}] symbol={s} caller={s} receiver=0x{x} step={d}\n",
                .{ ordinal, display_symbol, caller_label, recent.receiver, recent.step },
            );
        }
    }

    /// A tracked object's vptr was observed reading low and repaired by the
    /// vtable tracker. Scan results arrive as the zeroed slot offsets (bytes,
    /// ascending, including 0 for the vptr). Record the event and predict the
    /// casualty it produces: the next member call reading a zeroed header
    /// field carries a null receiver.
    pub fn noteObjectHeaderClobber(
        self: *Predictor,
        state: anytype,
        object_base: u64,
        type_symbol: []const u8,
        allocation_size: u64,
        zeroed_slots_bytes: []const u64,
        last_write_step: u64,
    ) void {
        var mask: u64 = 0;
        for (zeroed_slots_bytes) |off| {
            if (off % 8 != 0) continue;
            const slot: u6 = @intCast(@min(off / 8, 63));
            mask |= @as(u64, 1) << slot;
        }
        self.clobber[self.clobber_index] = .{
            .valid = true,
            .object_base = object_base,
            .type_symbol = type_symbol,
            .allocation_size = allocation_size,
            .zeroed_mask = mask,
            .step = state.executed_steps,
            .last_write_step = last_write_step,
        };
        self.clobber_index += 1;
        if (self.clobber_index == CLOBBER_CAPACITY) {
            self.clobber_index = 0;
            self.clobber_filled = true;
        }
        self.clobber_events +|= 1;

        // The zeroed-slot list is short and the event is rare, so building a
        // small string is fine. Slot 0 is the vptr — labelled restored, since
        // the tracker wrote the trusted value back over it.
        var slots_buf: [128]u8 = undefined;
        var slots_len: usize = 0;
        const head = "+0x0[vptr->restored]";
        @memcpy(slots_buf[0..head.len], head);
        slots_len = head.len;
        for (zeroed_slots_bytes) |off| {
            if (off == 0) continue;
            const part = std.fmt.bufPrint(slots_buf[slots_len..], ",+0x{x}", .{off}) catch break;
            slots_len += part.len;
        }
        machoCapturePrint(
            "NEAR NULL PREDICTOR: object_header_clobber object=0x{x} type={s} allocation_size={d} zeroed_slots={s} clobber_window=[{d}..{d}] writer=host-side write or alias-coherence defect (guest store widths are intercepted, so no guest instruction produced this unseen); predicted=the next native member call reading a zeroed header field will carry a null receiver — the lowest non-vptr zeroed offset is the prime suspect\n",
            .{
                object_base,
                type_symbol,
                allocation_size,
                slots_buf[0..slots_len],
                last_write_step,
                state.executed_steps,
            },
        );
    }

    /// A native (non-import) near-null casualty — a C++ member call whose
    /// receiver was null (`null_this`) or a tiny derived member offset
    /// (`derived_member_offset`). These never pass through import dispatch, so
    /// `note` can never see them; the causality engine records them here at
    /// the terminal fault, *before* the dump runs, so the terminal dump names
    /// the callee and caller with real symbols instead of reading empty. The
    /// shared signature table means the same casualty recurring in a later run
    /// (or a second casualty before exit) reports a growing count instead of
    /// silence.
    pub fn noteNativeReceiver(
        self: *Predictor,
        state: anytype,
        callee_address: u64,
        caller_address: u64,
        effective: u64,
        kind: NativeReceiverKind,
    ) void {
        self.native_receiver_events +|= 1;
        const signature = self.findOrInsertNative(callee_address, caller_address) orelse return;
        self.pushRecent("", caller_address, callee_address, effective, state.executed_steps);

        const step = state.executed_steps;
        const first_sight = signature.count == 0;
        const receiver_changed = signature.receiver != effective;
        signature.count +|= 1;
        const doubling_threshold = (signature.count & (signature.count - 1)) == 0;
        signature.receiver = effective;
        signature.last_seen_step = step;
        if (first_sight) signature.first_seen_step = step;

        if (first_sight or
            (receiver_changed and signature.emissions < MAX_EMISSIONS_PER_SIGNATURE) or
            (doubling_threshold and signature.emissions < MAX_EMISSIONS_PER_SIGNATURE))
        {
            signature.emissions +|= 1;
            self.emitNativeReceiver(state, signature, effective, kind);
        }
    }

    fn emitNativeReceiver(
        self: *Predictor,
        state: anytype,
        signature: *const Signature,
        effective: u64,
        kind: NativeReceiverKind,
    ) void {
        self.emissions +|= 1;
        const kind_label: []const u8 = switch (kind) {
            .null_this => "native_null_receiver",
            .derived_member_offset => "native_derived_receiver",
        };
        const explanation: []const u8 = switch (kind) {
            .null_this => "a native C++ member function ran with a null `this`; the caller above supplied the receiver — hunt the call that passed RDI=0 or the function that returned the object, and correlate with the object-header clobber history",
            .derived_member_offset => "the base register is a member offset into a partially-zeroed object — the same bypassing bulk-writer family as object_header_clobber; the faulting object's region was zeroed, so hunt the bulk write inside the window preceding this step and correlate with the clobber history",
        };
        var callee_buf: [symbolication.LABEL_BUFFER_BYTES]u8 = undefined;
        var caller_buf: [symbolication.LABEL_BUFFER_BYTES]u8 = undefined;
        machoCapturePrint(
            "NEAR NULL PREDICTOR: {s} effective=0x{x} member_offset=0x{x} callee={s} caller={s} count={d} step={d} threshold=0x{x}; {s}\n",
            .{
                kind_label,
                effective,
                effective,
                resolveCallerLabel(state, signature.callee, &callee_buf),
                resolveCallerLabel(state, signature.caller, &caller_buf),
                signature.count,
                signature.last_seen_step,
                NEAR_NULL_LIMIT,
                explanation,
            },
        );
    }

    /// Recent object-header clobbers, oldest first. Called from the terminal
    /// near-null dump so a casualty whose callee read one of these objects'
    /// zeroed fields is correlated with its producer.
    pub fn dumpClobber(self: *Predictor, state: anytype) void {
        const count = self.clobberCount();
        if (count == 0) return;
        machoCapturePrint(
            "NEAR NULL PREDICTOR: object-header clobber history ({d}):\n",
            .{count},
        );
        for (0..count) |ordinal| {
            const event = self.clobberChronological(ordinal) orelse continue;
            machoCapturePrint(
                "  [{d}] object=0x{x} type={s} allocation_size={d} zeroed_mask=0x{x} clobber_step={d} age_steps={d} window=[{d}..{d}]\n",
                .{
                    ordinal,
                    event.object_base,
                    event.type_symbol,
                    event.allocation_size,
                    event.zeroed_mask,
                    event.step,
                    state.executed_steps -| event.step,
                    event.last_write_step,
                    event.step,
                },
            );
        }
        machoCapturePrint(
            "NEAR NULL PREDICTOR: if the terminal casualty's callee read one of these objects' zeroed header fields, the matching clobber event above is its producer — hunt the bypassing bulk write inside that window\n",
            .{},
        );
    }

    fn clobberCount(self: *const Predictor) usize {
        return if (self.clobber_filled) CLOBBER_CAPACITY else self.clobber_index;
    }

    fn clobberChronological(self: *const Predictor, ordinal: usize) ?ClobberEvent {
        const count = self.clobberCount();
        if (ordinal >= count) return null;
        const start: usize = if (self.clobber_filled) self.clobber_index else 0;
        const event = self.clobber[(start + ordinal) % CLOBBER_CAPACITY];
        return if (event.valid) event else null;
    }

    fn emitSignature(self: *Predictor, state: anytype, signature: *const Signature, first_sight: bool) void {
        self.emissions +|= 1;
        var caller_buf: [symbolication.LABEL_BUFFER_BYTES]u8 = undefined;
        var callee_buf: [symbolication.LABEL_BUFFER_BYTES]u8 = undefined;
        const caller_label = resolveCallerLabel(state, signature.caller, &caller_buf);
        const kind: []const u8 = if (first_sight) "first_sight" else "recurrence";
        machoCapturePrint(
            "NEAR NULL PREDICTOR: {s} symbol={s} caller={s} rdi=0x{x} count={d} step={d} threshold=0x{x}\n",
            .{ kind, signatureLabel(state, signature, &callee_buf), caller_label, signature.receiver, signature.count, signature.last_seen_step, NEAR_NULL_LIMIT },
        );
    }

    fn findOrInsert(self: *Predictor, symbol: []const u8, caller: u64) ?*Signature {
        return self.findOrInsertSlot(hashSignature(symbol, caller), symbol, caller, 0);
    }

    fn findOrInsertNative(self: *Predictor, callee: u64, caller: u64) ?*Signature {
        return self.findOrInsertSlot(hashSignatureAddress(callee, caller), "", caller, callee);
    }

    fn findOrInsertSlot(self: *Predictor, hash: u64, symbol: []const u8, caller: u64, callee: u64) ?*Signature {
        var index: usize = @intCast(hash % SIGNATURE_CAPACITY);
        var first_empty: ?usize = null;
        var probes: usize = 0;
        while (probes < SIGNATURE_CAPACITY) : (probes += 1) {
            const signature = &self.signatures[index];
            if (!signature.valid) {
                if (first_empty == null) first_empty = index;
                break;
            }
            if (signature.symbol_hash == hash and signature.caller == caller) return signature;
            index = (index + 1) % SIGNATURE_CAPACITY;
        }
        if (first_empty) |slot| {
            self.signatures[slot] = .{
                .valid = true,
                .symbol_hash = hash,
                .symbol = symbol,
                .caller = caller,
                .callee = callee,
                .receiver = 0,
                .count = 0,
                .emissions = 0,
                .first_seen_step = 0,
                .last_seen_step = 0,
            };
            self.distinct_signatures +|= 1;
            return &self.signatures[slot];
        }
        // Table full of distinct signatures. Evict the *least important*
        // signature — lowest hit count, oldest step as a tiebreak — so a
        // hot recurring behavior is never displaced by a one-off. (Evicting
        // by step alone thrashes when `executed_steps` is 0 during early
        // init, which is what made the old predictor print the same
        // `first_sight` over and over.)
        var victim: ?usize = null;
        var victim_count: u32 = std.math.maxInt(u32);
        var victim_step: u64 = std.math.maxInt(u64);
        for (&self.signatures, 0..) |*signature, i| {
            if (!signature.valid) continue;
            const better_count = signature.count < victim_count;
            const same_count = signature.count == victim_count and signature.last_seen_step < victim_step;
            if (better_count or same_count) {
                victim = i;
                victim_count = signature.count;
                victim_step = signature.last_seen_step;
            }
        }
        const slot = victim orelse return null;
        self.signatures[slot] = .{
            .valid = true,
            .symbol_hash = hash,
            .symbol = symbol,
            .caller = caller,
            .callee = callee,
            .receiver = 0,
            .count = 0,
            .emissions = 0,
            .first_seen_step = 0,
            .last_seen_step = 0,
        };
        return &self.signatures[slot];
    }

    fn pushRecent(self: *Predictor, symbol: []const u8, caller: u64, callee: u64, receiver: u64, step: u64) void {
        self.recent[self.recent_index] = .{ .symbol = symbol, .caller = caller, .callee = callee, .receiver = receiver, .step = step };
        self.recent_index += 1;
        if (self.recent_index == RECENT_CAPACITY) {
            self.recent_index = 0;
            self.recent_filled = true;
        }
    }

    fn recentCount(self: *const Predictor) usize {
        return if (self.recent_filled) RECENT_CAPACITY else self.recent_index;
    }

    fn recentChronological(self: *const Predictor, ordinal: usize) ?Recent {
        const count = self.recentCount();
        if (ordinal >= count) return null;
        const start: usize = if (self.recent_filled) self.recent_index else 0;
        return self.recent[(start + ordinal) % RECENT_CAPACITY];
    }

    fn hashSignature(symbol: []const u8, caller: u64) u64 {
        var hash: u64 = 0xcbf2_9ce4_8422_2325;
        for (symbol) |byte| {
            hash ^= byte;
            hash *%= 0x100_0000_01b3;
        }
        hash ^= caller;
        hash *%= 0x100_0000_01b3;
        return hash;
    }

    fn hashSignatureAddress(callee: u64, caller: u64) u64 {
        var hash: u64 = 0xcbf2_9ce4_8422_2325;
        hash ^= callee;
        hash *%= 0x100_0000_01b3;
        hash ^= caller;
        hash *%= 0x100_0000_01b3;
        return hash;
    }
};

/// The guest call site that entered the import thunk: the saved return
/// address at `[rsp]`. The native stack is *not* guest memory, so a
/// `guestMemoryConst` gate (as the first version used) always failed and every
/// caller collapsed to the thunk address — read the stack directly, exactly
/// like the proven `handleImport` path.
fn importCallerAddress(state: anytype) u64 {
    if (state.regs.rsp == 0) return state.regs.rip;
    const caller = state.read64(state.regs.rsp);
    return if (caller != 0) caller else state.regs.rip;
}

/// The display name of a signature's callee: resolved from the stored callee
/// address for native (non-import) casualties, else the import symbol slice.
fn signatureLabel(state: anytype, signature: *const Signature, buffer: []u8) []const u8 {
    if (signature.callee != 0) return resolveCallerLabel(state, signature.callee, buffer);
    return signature.symbol;
}

/// Format a complete label for `caller`: `name+0xOFF@0xADDR` when a symbol
/// covers it, and otherwise a label naming *why* it has no symbol — outside
/// the image (generated code, heap, stack), inside the image with no covering
/// symbol, or no symbol table at this call site. The raw address is always
/// present so an unattributable caller stays solvable offline.
///
/// The label is written into the caller-owned `buffer` and is only valid until
/// that buffer is reused — never call this twice and keep both results, since
/// the second call overwrites the first's backing bytes. The buffer must be
/// `symbolication.LABEL_BUFFER_BYTES`: the mangled names here run past two
/// hundred characters, and a short buffer reports itself rather than
/// truncating.
fn resolveCallerLabel(state: anytype, caller: u64, buffer: []u8) []const u8 {
    // Delegated to the one owner of address-to-name. The version that lived
    // here tested `@hasDecl(@TypeOf(state.*), "metadata")`, and `metadata` is a
    // *field* — `@hasDecl` sees declarations only, so the test was always false
    // and every label this predictor printed read `<unknown>` while the frame
    // walk in the same dump named the identical addresses.
    return symbolication.describeState(state, caller, buffer);
}

// `isDocumentedNullSentinelImport` and `isBenignSmallIntArgImport` used to
// live here as two inline string tables walked on every near-null dispatch.
// Both answered a question fixed by the callee's declared signature, so they
// moved to `pkg/common/abi/receiver-classification`, which also names the
// class instead of collapsing it to a boolean — a zero-argument function and
// a documented null default are dismissed for different reasons, and the
// report now says which.

test "predictor records first sight and recurrence separately" {
    const TestState = struct {
        regs: struct {
            rdi: u64 = 0,
            rip: u64 = 0x1000,
            rsp: u64 = 0x8000,
        } = .{},
        mem: [64]u8 = [_]u8{0} ** 64,
        executed_steps: u64 = 0,

        fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            _ = self;
            _ = address;
            _ = length;
            return null;
        }

        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0x2000;
        }
    };

    var predictor = Predictor{};
    var state = TestState{};
    state.regs.rdi = 0;
    state.executed_steps = 10;
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u64, 1), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u32, 1), predictor.distinct_signatures);
    const signature = predictor.findOrInsert("_ZStls...EPKc", 0x2000).?;
    try std.testing.expectEqual(@as(u32, 1), signature.count);
    try std.testing.expectEqual(@as(u32, 1), signature.emissions);

    // A sane receiver is ignored entirely.
    state.regs.rdi = 0x10000;
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u64, 1), predictor.near_null_dispatches);

    // Recurrence with the same receiver re-emits only at a doubling threshold
    // (count 2 is a power of two) and stays quiet otherwise.
    state.regs.rdi = 0;
    state.executed_steps = 20;
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u32, 2), signature.count);
    try std.testing.expectEqual(@as(u32, 2), signature.emissions);

    state.executed_steps = 30;
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u32, 3), signature.count);
    try std.testing.expectEqual(@as(u32, 2), signature.emissions);

    // A different symbol is a new distinct signature.
    predictor.note(&state, "_ZSt4endl...");
    try std.testing.expectEqual(@as(u32, 2), predictor.distinct_signatures);
}

test "predictor reads the real caller off the native stack even when guestMemoryConst declines it" {
    // The first predictor version gated the caller read on guestMemoryConst,
    // which the native stack fails — every caller collapsed to `<unknown>`.
    var predictor = Predictor{};
    const TestState = struct {
        regs: struct {
            rdi: u64 = 0,
            rip: u64 = 0x1000,
            rsp: u64 = 0x70000000,
        } = .{},
        executed_steps: u64 = 0,

        fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            _ = self;
            _ = address;
            _ = length;
            return null;
        }

        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0x2cc511;
        }
    };
    var state = TestState{};
    predictor.note(&state, "_ZStls...EPKc");
    const signature = predictor.findOrInsert("_ZStls...EPKc", 0x2cc511).?;
    try std.testing.expectEqual(@as(u32, 1), signature.count);
    try std.testing.expectEqual(@as(u64, 0x2cc511), signature.caller);
}

test "predictor skips benign small-int-arg imports but counts them" {
    var predictor = Predictor{};
    const TestState = struct {
        regs: struct {
            rdi: u64 = 0,
            rip: u64 = 0x1000,
            rsp: u64 = 0x8000,
        } = .{},
        executed_steps: u64 = 0,

        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0x2000;
        }
    };
    var state = TestState{};
    state.executed_steps = 10;

    // operator new with a tiny size: near-null rdi but never a receiver.
    predictor.note(&state, "__Znwm");
    try std.testing.expectEqual(@as(u64, 1), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u64, 1), predictor.benign_skipped);
    try std.testing.expectEqual(@as(u32, 0), predictor.distinct_signatures);

    // fd-arg syscall with a suffix variant.
    predictor.note(&state, "_fstatat$INODE64");
    try std.testing.expectEqual(@as(u64, 2), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u64, 2), predictor.benign_skipped);
    try std.testing.expectEqual(@as(u32, 0), predictor.distinct_signatures);

    // The run's actual retained set: aligned operator new (size), signal
    // numbers, GTK enums, ffs value, CCCrypt operation, time(NULL).
    predictor.note(&state, "__ZnwmSt11align_val_t");
    predictor.note(&state, "_sigaction");
    predictor.note(&state, "_gtk_box_new");
    predictor.note(&state, "_ffs");
    predictor.note(&state, "_CCCrypt");
    predictor.note(&state, "_time");
    try std.testing.expectEqual(@as(u64, 8), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u64, 8), predictor.benign_skipped);
    try std.testing.expectEqual(@as(u32, 0), predictor.distinct_signatures);

    // This run's retained pair: steady_clock::now() (zero-arg static, rdi is
    // register garbage) and asctime(NULL) (Darwin tolerates, never a casualty).
    predictor.note(&state, "__ZNSt3__16chrono12steady_clock3nowEv");
    predictor.note(&state, "__ZNSt3__16chrono11system_clock3nowEv");
    predictor.note(&state, "_asctime");
    try std.testing.expectEqual(@as(u64, 11), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u64, 11), predictor.benign_skipped);
    try std.testing.expectEqual(@as(u32, 0), predictor.distinct_signatures);

    // A receiver-shaped import is still recorded.
    predictor.note(&state, "_ZStls...EPKc");
    try std.testing.expectEqual(@as(u64, 12), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u32, 1), predictor.distinct_signatures);
}

test "predictor full-table eviction prefers the least-used signature" {
    var predictor = Predictor{};
    const TestState = struct {
        regs: struct {
            rdi: u64 = 0,
            rip: u64 = 0x1000,
            rsp: u64 = 0x8000,
        } = .{},
        executed_steps: u64 = 0,

        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0x2000;
        }
    };
    var state = TestState{};
    state.executed_steps = 10;

    // Fill the table with distinct signatures.
    var i: usize = 0;
    while (i < SIGNATURE_CAPACITY) : (i += 1) {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "sym_{d}", .{i}) catch unreachable;
        predictor.note(&state, name);
        state.executed_steps += 1;
    }
    try std.testing.expectEqual(@as(u32, @intCast(SIGNATURE_CAPACITY)), predictor.distinct_signatures);

    // Make the first signature hot by re-hitting it several times.
    var j: usize = 0;
    while (j < 8) : (j += 1) {
        predictor.note(&state, "sym_0");
        state.executed_steps += 1;
    }
    const hot = predictor.findOrInsert("sym_0", 0x2000).?;
    try std.testing.expectEqual(@as(u32, 9), hot.count);

    // Inserting one more distinct signature evicts the least-used entry, and
    // the hot one survives.
    predictor.note(&state, "sym_extra");
    try std.testing.expectEqual(@as(u32, @intCast(SIGNATURE_CAPACITY)), predictor.distinct_signatures);
    try std.testing.expectEqual(@as(u32, 9), predictor.findOrInsert("sym_0", 0x2000).?.count);
}

test "predictor records object-header clobbers and builds the zeroed-slot mask" {
    var predictor = Predictor{};
    const TestState = struct {
        executed_steps: u64 = 0,
    };
    var state = TestState{};
    state.executed_steps = 1_000_000;

    // The UserModule casualty shape from the run: header zeroed through +0x10
    // by a bypassing bulk write, vptr restored by the tracker.
    const zeroed = [_]u64{ 0, 0x8, 0x10 };
    predictor.noteObjectHeaderClobber(
        &state,
        0x17202dd0,
        "__ZTVN2xe6kernel10UserModuleE",
        224,
        &zeroed,
        69_975_627,
    );
    try std.testing.expectEqual(@as(u64, 1), predictor.clobber_events);
    try std.testing.expectEqual(@as(usize, 1), predictor.clobberCount());
    const event = predictor.clobberChronological(0).?;
    try std.testing.expectEqual(@as(u64, 0x17202dd0), event.object_base);
    // Bits 0, 1, 2 set (slots at +0x0, +0x8, +0x10).
    try std.testing.expectEqual(@as(u64, 0b111), event.zeroed_mask);
    try std.testing.expectEqual(@as(u64, 1_000_000), event.step);
    try std.testing.expectEqual(@as(u64, 69_975_627), event.last_write_step);

    // A second clobber on a different object is recorded as a separate event.
    state.executed_steps = 2_000_000;
    const zeroed2 = [_]u64{ 0, 0x8 };
    predictor.noteObjectHeaderClobber(&state, 0x18000000, "__ZTVN2xe3cpu9XexModuleE", 512, &zeroed2, 1_900_000);
    try std.testing.expectEqual(@as(u64, 2), predictor.clobber_events);
    try std.testing.expectEqual(@as(usize, 2), predictor.clobberCount());
    try std.testing.expectEqual(@as(u64, 0b11), predictor.clobberChronological(1).?.zeroed_mask);

    // Ring wrap: more events than capacity keep only the most recent.
    var i: usize = 0;
    while (i < CLOBBER_CAPACITY + 2) : (i += 1) {
        state.executed_steps += 1;
        const z = [_]u64{0};
        predictor.noteObjectHeaderClobber(&state, 0x2000_0000 + i, "type", 64, &z, 0);
    }
    try std.testing.expectEqual(@as(usize, CLOBBER_CAPACITY), predictor.clobberCount());
}

// Every signature one observed run retained was a correct call. A predictor
// whose whole retained set is false positives is worse than silence: it trains
// the reader to skip its output, and the one real prediction arrives inside
// noise that has already been learned to ignore.
test "correct calls with a small first argument are not retained as predictions" {
    const TestState = struct {
        regs: struct { rdi: u64 = 0, rip: u64 = 0x1000, rsp: u64 = 0x7000_0000 } = .{},
        executed_steps: u64 = 0,
        fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            _ = self;
            _ = address;
            _ = length;
            return null;
        }
        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0x30908b;
        }
    };

    // Exactly the retained set from the observed run, with its observed rdi.
    const observed = [_]struct { symbol: []const u8, rdi: u64 }{
        .{ .symbol = "_abs", .rdi = 0x1 }, // abs(1)
        .{ .symbol = "_abs", .rdi = 0x60 }, // abs(96)
        .{ .symbol = "_abs", .rdi = 0x0 }, // abs(0)
        .{ .symbol = "_abs", .rdi = 0x50 }, // abs(80)
        .{ .symbol = "_abs", .rdi = 0x3 }, // abs(3)
        .{ .symbol = "_SDL_InitSubSystem", .rdi = 0x10 }, // SDL_INIT_AUDIO
        .{ .symbol = "_SDL_OpenAudioDevice", .rdi = 0x0 }, // NULL = default device
        .{ .symbol = "_SDL_PauseAudioDevice", .rdi = 0x101 }, // device id 257
    };

    var predictor = Predictor{};
    var state = TestState{};
    for (observed) |call| {
        state.regs.rdi = call.rdi;
        predictor.note(&state, call.symbol);
    }

    // Counted, so the accounting still adds up, but nothing retained.
    try std.testing.expectEqual(@as(u64, observed.len), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u64, observed.len), predictor.benign_skipped);
    try std.testing.expectEqual(@as(u32, 0), predictor.distinct_signatures);
    try std.testing.expectEqual(@as(usize, 0), predictor.recent_index);
    try std.testing.expect(!predictor.recent_filled);
}

// The suppression must be narrow. An SDL entry point that really does take a
// pointer receiver has to keep predicting, or widening the list would quietly
// blind the tool to the class of bug it exists for.
test "a genuine null receiver is still retained after the benign lists grow" {
    const TestState = struct {
        regs: struct { rdi: u64 = 0, rip: u64 = 0x1000, rsp: u64 = 0x7000_0000 } = .{},
        executed_steps: u64 = 0,
        fn guestMemoryConst(self: *const @This(), address: u64, length: u64) ?[]const u8 {
            _ = self;
            _ = address;
            _ = length;
            return null;
        }
        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0x4444;
        }
    };
    var predictor = Predictor{};
    var state = TestState{};

    // Takes SDL_AudioSpec*/SDL_Surface* — null here is a real defect.
    state.regs.rdi = 0;
    predictor.note(&state, "_SDL_FreeSurface");
    predictor.note(&state, "_SDL_GameControllerName");
    // A C++ member function is always receiver-shaped.
    predictor.note(&state, "__ZNK2xe6kernel11KernelState6memoryEv");

    try std.testing.expectEqual(@as(u64, 3), predictor.near_null_dispatches);
    try std.testing.expectEqual(@as(u64, 0), predictor.benign_skipped);
    try std.testing.expectEqual(@as(u32, 3), predictor.distinct_signatures);
}

test "the dismissal reasons stay separate and neither swallows the other" {
    // The classification moved to `pkg/common/abi/receiver-classification`, so
    // this asserts the behaviour the predictor depends on rather than the
    // table's shape: the reasons must stay distinguishable, and none of them
    // may claim a receiver-shaped symbol.
    const Class = receiver_classification.Class;

    // Not a pointer at all.
    try std.testing.expectEqual(Class.scalar_first_argument, receiver_classification.classify("_abs"));
    try std.testing.expectEqual(Class.scalar_first_argument, receiver_classification.classify("_raise"));
    try std.testing.expectEqual(
        Class.scalar_first_argument,
        receiver_classification.classify("_SDL_PauseAudioDevice"),
    );

    // No argument at all — the class the `_getpagesize` false positive needed.
    // A run reported it three times with a stale `rdi=0x2`, directly above the
    // one real finding in the same dump.
    try std.testing.expectEqual(Class.no_arguments, receiver_classification.classify("_getpagesize"));

    // libc++ basic_ostream::sentry destructors: the primitive handler is a
    // no-op that never dereferences the receiver, so a near-null rdi (the
    // guest-stack sentry guard) predicts nothing. Both observed and
    // version-tagged spellings are covered by the `6sentryD` family check.
    for ([_][]const u8{
        "__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryD1Ev",
        "__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryD2Ev",
        "__ZNSt3__113basic_ostreamIcNS_11char_traitsIcEEE6sentryD1B7v160006Ev",
    }) |sentry| {
        try std.testing.expect(!receiver_classification.predictsCasualty(sentry));
    }

    // A real pointer whose null value is the documented default. Distinct from
    // the scalar class because only the API contract dismisses it.
    try std.testing.expectEqual(
        Class.nullable_pointer_first_argument,
        receiver_classification.classify("_SDL_OpenAudioDevice"),
    );

    // No class may claim a receiver-shaped symbol.
    try std.testing.expectEqual(Class.receiver, receiver_classification.classify("_SDL_FreeSurface"));
    try std.testing.expect(receiver_classification.predictsCasualty("_SDL_FreeSurface"));
}

// Native member-call casualties never pass through import dispatch, so the
// import-watching `note` can never see them — the run's predictor dump read
// `distinct=0 retained=0` while the terminal fault was a derived receiver. The
// causality engine records them into the shared signature table, keyed by
// (callee, caller), so the dump names the crash with real symbols instead of
// silence.
test "predictor records native receiver casualties with resolved callee symbols" {
    const TestState = struct {
        regs: struct { rdi: u64 = 0, rip: u64 = 0x1000, rsp: u64 = 0x8000, rbp: u64 = 0 } = .{},
        executed_steps: u64 = 0,

        fn read64(self: *const @This(), address: u64) u64 {
            _ = self;
            _ = address;
            return 0x2000;
        }
    };

    var predictor = Predictor{};
    var state = TestState{};
    state.executed_steps = 5_134_999_999;

    // The Xbyak LabelManager casualty: std::__hash_table::begin() with
    // this=0x48 — the `undefList` member offset into a partially-zeroed
    // emitter whose stateList_ head was cleared by the bypassing bulk writer.
    // callee=the terminal function, caller=frame[1]'s return site.
    predictor.noteNativeReceiver(&state, 0xd84871, 0xd84745, 0x48, .derived_member_offset);
    try std.testing.expectEqual(@as(u64, 1), predictor.native_receiver_events);
    try std.testing.expectEqual(@as(u32, 1), predictor.distinct_signatures);
    const signature = predictor.findOrInsertNative(0xd84871, 0xd84745).?;
    try std.testing.expectEqual(@as(u32, 1), signature.count);
    try std.testing.expectEqual(@as(u64, 0xd84871), signature.callee);
    try std.testing.expectEqual(@as(u64, 0xd84745), signature.caller);
    try std.testing.expectEqual(@as(u64, 0x48), signature.receiver);
    try std.testing.expectEqual(@as(usize, 1), predictor.recentCount());

    // Same callee+caller recurs -> the same signature accumulates a count.
    state.executed_steps = 5_135_000_000;
    predictor.noteNativeReceiver(&state, 0xd84871, 0xd84745, 0x48, .derived_member_offset);
    try std.testing.expectEqual(@as(u32, 2), signature.count);
    try std.testing.expectEqual(@as(u32, 1), predictor.distinct_signatures);

    // A null-this native casualty (KernelState::memory with this=0) is a new
    // distinct signature and keeps the effective address as its receiver.
    predictor.noteNativeReceiver(&state, 0x20fe9c, 0x872099, 0x58, .null_this);
    try std.testing.expectEqual(@as(u32, 2), predictor.distinct_signatures);
    try std.testing.expectEqual(@as(u64, 0x58), predictor.findOrInsertNative(0x20fe9c, 0x872099).?.receiver);

    // Import and native signatures share the table without colliding.
    const import_signature = predictor.findOrInsert("_ZStls...EPKc", 0x2000).?;
    try std.testing.expectEqual(@as(u32, 3), predictor.distinct_signatures);
    try std.testing.expectEqual(@as(u64, 0), import_signature.callee);
    try std.testing.expectEqual(@as(u64, 0xd84871), predictor.findOrInsertNative(0xd84871, 0xd84745).?.callee);
}
