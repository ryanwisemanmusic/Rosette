const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_block_jit = @import("block_jit.zig");
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_guest_memory = @import("guest_memory.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const process_impl_lifecycle = @import("lifecycle.zig");
const __process_DecodeCacheCounters = __ProcessInternals._DecodeCacheCounters;
const __process_DecodeCacheEntry = __ProcessInternals._DecodeCacheEntry;
const __process_DecodeCacheMissCause = __ProcessInternals._DecodeCacheMissCause;
const __process_DecodeCacheMissSite = __ProcessInternals._DecodeCacheMissSite;
const __process_DecodeCacheShard = __ProcessInternals._DecodeCacheShard;
const __process_DecodedInsn = __ProcessInternals._DecodedInsn;
const __process_GuestContextRef = __ProcessInternals._GuestContextRef;
const __process_PE_DECODE_CACHE_LOCAL_ENTRIES = __ProcessInternals._PE_DECODE_CACHE_LOCAL_ENTRIES;
const __process_PE_DECODE_CACHE_VICTIM_WAYS = __ProcessInternals._PE_DECODE_CACHE_VICTIM_WAYS;
const __process_PE_DECODE_CACHE_WAYS = __ProcessInternals._PE_DECODE_CACHE_WAYS;
const __process_PE_MAX_INSTRUCTION_LENGTH = __ProcessInternals._PE_MAX_INSTRUCTION_LENGTH;
const __process_RegId = __ProcessInternals._RegId;
const __process_Size = __ProcessInternals._Size;
const __process_WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE = __ProcessInternals._WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE;
const __process_WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP = __ProcessInternals._WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP;
const __process_WindowsMappedCodeSlice = __ProcessInternals._WindowsMappedCodeSlice;
const __process_WorkerLocalDecodeCache = __ProcessInternals._WorkerLocalDecodeCache;
const __process_concurrency = __ProcessInternals._concurrency;
const __process_decodeInsn = __ProcessInternals._decodeInsn;
const __process_decode_cache_miss_mutex = __ProcessInternals._decode_cache_miss_mutex;
const __process_decode_cache_set_lock_count = __ProcessInternals._decode_cache_set_lock_count;
const __process_decode_cache_set_locks = __ProcessInternals._decode_cache_set_locks;
const __process_guest_clock = __ProcessInternals._guest_clock;
const __process_guest_symbol_text_bytes = __ProcessInternals._guest_symbol_text_bytes;
const __process_log = __ProcessInternals._log;
const __process_monotonicNanoseconds = __ProcessInternals._monotonicNanoseconds;
const __process_peDecodeCacheIndex = __ProcessInternals._peDecodeCacheIndex;
const __process_peDecodeCacheSetIndex = __ProcessInternals._peDecodeCacheSetIndex;
const __process_peDecodeCacheVictimIndex = __ProcessInternals._peDecodeCacheVictimIndex;
const __process_std = __ProcessInternals._std;
const __process_tso_memory = __ProcessInternals._tso_memory;
const __process_x64_decoder = __ProcessInternals._x64_decoder;
const __state_DecodeCacheVictimHit = __StateInternals._DecodeCacheVictimHit;

pub fn terminateUnimplemented(self: *ElfState, d: __process_DecodedInsn) void {
    process_impl_lifecycle.markFaulted(self);
    self.exit_code = 127;
    self.termination_reason = .unimplemented_instruction;
    process_impl_lifecycle.markTerminated(self);
    // Keep the production failure visible, while avoiding an intentional
    // negative-path unit test being reclassified as a test-runner error
    // solely because it exercises this fatal diagnostic.
    if (comptime !@import("builtin").is_test) {
        __process_log.err("unimplemented x86-64 instruction at rip=0x{x}: {s}", .{ process_impl_lifecycle.guestContextField(self, "regs").*.rip, @tagName(d.op) });
    }
}

pub fn raiseDivideError(self: *ElfState) void {
    process_impl_lifecycle.markFaulted(self);
    self.exit_code = 127;
    self.termination_reason = .divide_by_zero;
    process_impl_lifecycle.markTerminated(self);
    if (comptime !@import("builtin").is_test) {
        __process_log.err("x86 divide error at rip=0x{x} op={s}", .{ process_impl_lifecycle.guestContextField(self, "regs").*.rip, @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*) });
    }
}

pub fn sibAddr(self: *const ElfState, d: *__process_DecodedInsn) void {
    d.addr = __process_x64_decoder.resolveMemoryAddress(&process_impl_lifecycle.guestContextField(self, "regs").*, .{
        .displacement = d.addr,
        .has_index = d.sib_has_index,
        .index_reg = d.sib_index_reg,
        .scale = d.sib_scale,
        .has_base = d.sib_has_base,
        .base_reg = d.sib_base_reg,
        .rip_relative = d.rip_relative,
        .segment = d.segment,
    }, process_impl_lifecycle.guestContextField(self, "regs").*.rip +% d.len, .bits64, .long64, true);
}

pub fn noteWindowsTitleCodeFetch(self: *ElfState, address: u64) void {
    noteWindowsTitleCodeFetches(self, address, 1);
}

pub fn noteWindowsTitleCodeFetches(self: *ElfState, address: u64, count: u64) void {
    noteWindowsTitleCodeFetchesIn(self, process_impl_lifecycle.guestContextRef(self), address, count);
}

pub fn noteWindowsTitleCodeFetchesIn(self: *ElfState, ctx: __process_GuestContextRef, address: u64, count: u64) void {
    const slot = ctx.field("windows_active_guest_thread_slot").* orelse return;
    if (!self.windows_guest_threads[slot].entered_xenia_title) return;
    const index = self.windows_code_cache_view orelse return;
    // By reference: this runs once per translated block - eighteen
    // billion times on 2026-09-20 - and the view is not a scalar.
    const view = &self.windows_memory_views[index];
    if (address >= view.guest_base and address - view.guest_base < view.length) {
        self.windows_title_code_fetches +|= count;
    }
}

pub fn guestInstructionBytes(self: *const ElfState, address: u64, buffer: *[16]u8) []const u8 {
    if (process_impl_guest_memory.addrToOffset(self, address)) |offset| {
        if (offset < self.mem.len) {
            const count = @min(self.mem.len - offset, buffer.len);
            process_impl_block_jit.copyGuestCode(self, buffer[0..count], self.mem[offset..][0..count]);
            return buffer[0..count];
        }
    }
    var count: u64 = buffer.len;
    while (count != 0) : (count -= 1) {
        if (process_impl_guest_memory.windowsMappedCodeMemoryConst(self, address, count)) |slice| {
            const available: usize = @intCast(@min(slice.bytes.len, count));
            process_impl_block_jit.copyGuestCode(self, buffer[0..available], slice.bytes[0..available]);
            return buffer[0..available];
        }
    }
    return buffer[0..0];
}

pub fn decodeCacheWorkerLocalHits(self: *const ElfState) u64 {
    const counter = @constCast(&self.decode_cache_worker_local_hits);
    __process_WorkerLocalDecodeCache.publishHits(counter);
    return counter.load(.monotonic);
}

pub fn decodeCacheCounts(self: *const ElfState) __process_DecodeCacheCounters {
    var total: __process_DecodeCacheCounters = .{};
    // Workers update each shard under its matching set lock. Take that
    // lock while sampling so periodic telemetry does not race the hot
    // path's plain counters; only one lock is held at a time.
    for (self.decode_cache_shards, 0..) |shard, index| {
        const lock = &__ProcessInternals._decode_cache_set_locks().*[index];
        lock.lock();
        total.accumulate(shard.counters);
        lock.unlock();
    }
    total.worker_local_hits = decodeCacheWorkerLocalHits(self);
    total.hits +|= total.worker_local_hits;
    return total;
}

pub fn logWorkerLocalDecodeCache(self: *const ElfState, counts: __process_DecodeCacheCounters, lookups: u64) void {
    const hit_share_ppm = if (lookups == 0) 0 else @divTrunc(counts.worker_local_hits *| 1_000_000, lookups);
    __process_log.info("PE64 DECODE CACHE WORKER LOCAL: entries={d} hits={d} share_of_all_lookups_ppm={d} parallel={}; the private tier still validates instruction bytes through coordinated access before using a decode", .{
        __process_PE_DECODE_CACHE_LOCAL_ENTRIES,
        counts.worker_local_hits,
        hit_share_ppm,
        self.parallel_guest_execution,
    });
}

pub fn touchDecodeCachePrimaryEntry(entry: *__process_DecodeCacheEntry, shard: *__process_DecodeCacheShard) void {
    // Each cache set always maps to one shard and is protected by that
    // shard's mutex in parallel mode. Its sixteen residents therefore
    // have comparable recency without a process-wide write on every hit.
    shard.age_clock +|= 1;
    entry.last_used = shard.age_clock;
}

pub fn touchDecodeCacheVictimEntry(self: *ElfState, entry: *__process_DecodeCacheEntry) void {
    // Victim sets combine evictions from multiple primary shards, so they
    // retain one LRU clock under `decode_cache_miss_mutex`. This runs only
    // on misses, never on the hot primary hit path.
    if (self.decode_cache_clock == __process_std.math.maxInt(u64)) {
        for (self.decode_cache_victims) |*candidate| candidate.last_used = 0;
        self.decode_cache_clock = 1;
    } else {
        self.decode_cache_clock += 1;
    }
    entry.last_used = self.decode_cache_clock;
}

pub fn decodeCacheEntryHasIdentity(
    entry: *const __process_DecodeCacheEntry,
    fetch_address: u64,
    mapped_code: ?__process_WindowsMappedCodeSlice,
) bool {
    if (!entry.valid or entry.fetch_address != fetch_address or entry.mapped_source != (mapped_code != null)) return false;
    if (mapped_code) |generated| {
        return entry.source_index == generated.source_index and entry.source_kind == generated.kind;
    }
    return true;
}

pub fn saveDecodeCacheVictim(self: *ElfState, evicted: *const __process_DecodeCacheEntry, shard: *__process_DecodeCacheShard) void {
    if (!evicted.valid) return;
    const set_base = __process_peDecodeCacheVictimIndex(evicted.fetch_address);
    const ways = self.decode_cache_victims[set_base..][0..__process_PE_DECODE_CACHE_VICTIM_WAYS];
    var selected: ?*__process_DecodeCacheEntry = null;
    var oldest: u64 = __process_std.math.maxInt(u64);
    for (ways) |*candidate| {
        if (!candidate.valid or candidate.fetch_address == evicted.fetch_address) {
            selected = candidate;
            break;
        }
        if (candidate.last_used < oldest) {
            oldest = candidate.last_used;
            selected = candidate;
        }
    }
    selected.?.* = evicted.*;
    touchDecodeCacheVictimEntry(self, selected.?);
    shard.counters.victim_fills +|= 1;
}

pub fn findDecodeCacheVictim(
    self: *ElfState,
    fetch_address: u64,
    bytes: []const u8,
    remaining: usize,
    mapped_code: ?__process_WindowsMappedCodeSlice,
    shard: *__process_DecodeCacheShard,
) ?__state_DecodeCacheVictimHit {
    const set_base = __process_peDecodeCacheVictimIndex(fetch_address);
    const ways = self.decode_cache_victims[set_base..][0..__process_PE_DECODE_CACHE_VICTIM_WAYS];
    for (ways) |*candidate| {
        if (!decodeCacheEntryHasIdentity(candidate, fetch_address, mapped_code)) continue;
        const cached_len = @as(usize, candidate.decoded.len);
        const same_source = cached_len != 0 and cached_len <= remaining and
            cached_len <= __process_PE_MAX_INSTRUCTION_LENGTH;
        if (!same_source) continue;
        const image_generation: ?u64 = if (mapped_code == null and !self.parallel_guest_execution)
            process_impl_guest_memory.windowsImageCodeGenerationFor(self, fetch_address, cached_len)
        else
            null;
        const generation_matches = if (self.parallel_guest_execution)
            false
        else if (mapped_code) |generated|
            candidate.source_generation == generated.generation
        else if (image_generation) |generation|
            candidate.source_generation == generation
        else
            false;
        const bytes_match = __process_std.mem.eql(u8, candidate.bytes[0..cached_len], bytes[0..cached_len]);
        if (generation_matches or bytes_match) {
            const rearmed = !generation_matches and bytes_match;
            if (mapped_code) |generated| candidate.source_generation = generated.generation;
            if (mapped_code == null) {
                if (image_generation) |generation| candidate.source_generation = generation;
            }
            return .{ .entry = candidate, .rearmed = rearmed };
        }
        candidate.valid = false;
        shard.counters.victim_stale_rejections +|= 1;
    }
    return null;
}

pub fn noteDecodeCacheMiss(
    self: *ElfState,
    cause: __process_DecodeCacheMissCause,
    fetch_address: u64,
    set_index: usize,
    resident_addresses: [__process_PE_DECODE_CACHE_WAYS]u64,
    resident_count: usize,
    mapped_code: ?__process_WindowsMappedCodeSlice,
    shard: *__process_DecodeCacheShard,
) void {
    switch (cause) {
        .vacant_fill => shard.counters.vacant_fills +|= 1,
        .capacity_conflict => {
            shard.counters.conflict_fills +|= 1;
            shard.counters.collisions +|= 1;
            if (mapped_code != null) {
                shard.counters.generated_conflict_fills +|= 1;
            } else {
                shard.counters.image_conflict_fills +|= 1;
            }
        },
        .stale_bytes => shard.counters.stale_refills +|= 1,
    }

    // A compulsory fill is expected. A full-set replacement or a source
    // byte change is not: both mean an instruction that was already in
    // the execution stream could not be reused safely. Keep the warning
    // sparse, but route every decisive event through the same fatal-point
    // policy used by the PE wait/import/memory diagnostics.
    //
    // The throttle counts across every shard. Counting per shard let
    // each of the 4096 shards report its own first fills: on 2026-09-30
    // that was 20,000 of the log's 22,014 lines, written while this path
    // held a set lock and the miss mutex, so the owner spent 82% of its
    // wall time in writev and every other executor's miss queued behind.
    const report = &self.decode_cache_miss_reports[@intFromEnum(cause)];
    report.* +|= 1;
    const occurrence = report.*;

    const source_index = if (mapped_code) |source| source.source_index else 0;
    const source_kind = if (mapped_code) |source| source.kind else .memory_view;
    const source_generation = if (mapped_code) |source| source.generation else 0;
    // A compulsory fill is the working set arriving: counted, never
    // listed. The run's first 256 instructions used to take every site,
    // so a later conflict or stale refill - the findings this table
    // exists to name - could only ever be counted as overflow.
    var site: ?*__process_DecodeCacheMissSite = null;
    if (cause != .vacant_fill) {
        for (self.decode_cache_miss_sites[0..self.decode_cache_miss_site_count]) |*candidate| {
            if (candidate.cause == cause and candidate.fetch_address == fetch_address and
                candidate.set_index == set_index and candidate.mapped_source == (mapped_code != null) and
                candidate.source_kind == source_kind and candidate.source_index == source_index)
            {
                site = candidate;
                break;
            }
        }
        if (site == null and self.decode_cache_miss_site_count < self.decode_cache_miss_sites.len) {
            site = &self.decode_cache_miss_sites[self.decode_cache_miss_site_count];
            self.decode_cache_miss_site_count += 1;
            site.?.* = .{
                .cause = cause,
                .fetch_address = fetch_address,
                .set_index = set_index,
                .mapped_source = mapped_code != null,
                .source_kind = source_kind,
                .source_index = source_index,
                .source_generation = source_generation,
                .resident_addresses = resident_addresses,
                .resident_count = resident_count,
                .occurrences = 0,
                .first_step = process_impl_lifecycle.observedExecutionSteps(self),
                .first_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            };
        } else if (site == null) {
            self.decode_cache_miss_site_overflow +|= 1;
        }
    }
    if (site) |entry| {
        entry.occurrences +|= 1;
        entry.last_step = process_impl_lifecycle.observedExecutionSteps(self);
        entry.last_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
        entry.source_generation = source_generation;
    }

    if (self.windows_runtime_enabled and process_impl_guest_diagnostics.shouldReportWindowsPointOccurrence(occurrence)) {
        var resident_text: [__process_PE_DECODE_CACHE_WAYS * 24 + 1]u8 = undefined;
        var resident_text_len: usize = 0;
        for (resident_addresses[0..resident_count], 0..) |address, index| {
            const piece = __process_std.fmt.bufPrint(
                resident_text[resident_text_len..],
                "{s}{d}:0x{x}",
                .{ if (index == 0) "" else "/", index, address },
            ) catch break;
            resident_text_len += piece.len;
        }
        const classification = switch (cause) {
            .vacant_fill => "compulsory-first-touch",
            .capacity_conflict => if (mapped_code != null) "capacity-conflict-generated-code" else "capacity-conflict-image-code",
            .stale_bytes => "stale-executable-bytes",
        };
        const action = switch (cause) {
            .vacant_fill => "no action unless the same address repeats unexpectedly",
            .capacity_conflict => if (mapped_code != null)
                "inspect generated-code working-set pressure and cache-set residency"
            else
                "inspect image-code working-set pressure and cache-set residency",
            .stale_bytes => "inspect executable-write invalidation and self-modifying-code ownership",
        };
        __process_log.warn("PE64 DECODE CACHE FINDING: cause={s} classification={s} source={s} kind={s} source_index={d} generation={d} step={d} rip=0x{x} fetch=0x{x} set={d} ways={d} residents={s} policy={s} action={s}", .{
            cause.label(),
            classification,
            if (mapped_code != null) "generated-code" else "image-code",
            @tagName(source_kind),
            source_index,
            source_generation,
            process_impl_lifecycle.observedExecutionSteps(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rip,
            fetch_address,
            set_index,
            __process_PE_DECODE_CACHE_WAYS,
            resident_text[0..resident_text_len],
            if (self.windows_fatal_point_terminate and cause.fatalLabel().len != 0) "terminate-on-fatal" else "record-only",
            action,
        });
    }
    const fatal_label = cause.fatalLabel();
    if (self.windows_runtime_enabled and fatal_label.len != 0) {
        process_impl_guest_diagnostics.terminateForWindowsFatalPointWith(self, fatal_label, .runtime_invariant_failure, 126);
    }
}

pub fn reportDecodeCacheMissSites(self: *const ElfState) void {
    const counts = decodeCacheCounts(self);
    if (counts.misses == 0) return;
    const lookups = counts.hits +| counts.rearms +| counts.misses;
    const miss_rate_ppm = if (lookups == 0) 0 else @divTrunc(counts.misses *| 1_000_000, lookups);
    const conflict_rate_ppm = if (lookups == 0) 0 else @divTrunc(counts.conflict_fills *| 1_000_000, lookups);
    __process_log.info("PE64 DECODE CACHE FINDINGS: distinct_sites={d} overflow={d} lookups={d} miss_rate_ppm={d} conflict_rate_ppm={d} totals(vacant/conflict/stale)={d}/{d}/{d} conflict_sources(generated/image)={d}/{d}; conflicts and stale-byte refills are fatal when the PE fatal-point policy is armed", .{
        self.decode_cache_miss_site_count,
        self.decode_cache_miss_site_overflow,
        lookups,
        miss_rate_ppm,
        conflict_rate_ppm,
        counts.vacant_fills,
        counts.conflict_fills,
        counts.stale_refills,
        counts.generated_conflict_fills,
        counts.image_conflict_fills,
    });
    for (self.decode_cache_miss_sites[0..self.decode_cache_miss_site_count]) |site| {
        const classification = switch (site.cause) {
            .vacant_fill => "compulsory-first-touch",
            .capacity_conflict => if (site.mapped_source) "capacity-conflict-generated-code" else "capacity-conflict-image-code",
            .stale_bytes => "stale-executable-bytes",
        };
        const action = switch (site.cause) {
            .vacant_fill => "no action unless the address repeats unexpectedly",
            .capacity_conflict => if (site.mapped_source)
                "inspect generated-code set pressure; raising the cache is not a mapping fix"
            else
                "inspect image-code set pressure; raising the cache is not a mapping fix",
            .stale_bytes => "inspect executable write invalidation and code-generation ownership",
        };
        var residents: [__process_PE_DECODE_CACHE_WAYS * 24 + 1]u8 = undefined;
        var used: usize = 0;
        for (site.resident_addresses[0..site.resident_count], 0..) |address, index| {
            const piece = __process_std.fmt.bufPrint(residents[used..], "{s}0x{x}", .{ if (index == 0) "" else "/", address }) catch break;
            used += piece.len;
        }
        __process_log.info("PE64 DECODE CACHE FINDING: cause={s} classification={s} source={s} kind={s} source_index={d} generation={d} occurrences={d} first_step={d} last_step={d} first_rip=0x{x} last_rip=0x{x} set={d} residents={s} action={s}", .{
            site.cause.label(),
            classification,
            if (site.mapped_source) "generated-code" else "image-code",
            @tagName(site.source_kind),
            site.source_index,
            site.source_generation,
            site.occurrences,
            site.first_step,
            site.last_step,
            site.first_rip,
            site.last_rip,
            site.set_index,
            residents[0..used],
            action,
        });
    }
}

pub fn reportInvalidWindowsControlTarget(self: *ElfState, fetch_address: u64) bool {
    if (!self.windows_runtime_enabled) return false;
    const last_rip = process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*;
    const last_op = process_impl_lifecycle.guestContextField(self, "last_decoded_op").*;
    if (last_op != .call_reg64 and last_op != .call_mem64 and last_op != .jmp_reg64 and last_op != .jmp_mem64) return false;
    if (last_rip == 0) return false;

    var instruction_bytes: [16]u8 = undefined;
    const bytes = guestInstructionBytes(self, last_rip, &instruction_bytes);
    if (bytes.len == 0) return false;
    const decoded = __process_decodeInsn(bytes);
    if (decoded.len == 0 or decoded.op != last_op) return false;

    var source_address: u64 = 0;
    var target: u64 = 0;
    var source_label: []const u8 = "unknown";
    if (decoded.op == .call_reg64 or decoded.op == .jmp_reg64) {
        source_address = process_impl_execution.regVal(self, decoded.dst_reg, .bits64);
        target = source_address;
        source_label = @tagName(decoded.dst_reg);
    } else {
        const regs = process_impl_lifecycle.guestContextField(self, "regs").*;
        source_address = __process_x64_decoder.resolveMemoryAddress(&regs, .{
            .displacement = decoded.addr,
            .has_index = decoded.sib_has_index,
            .index_reg = decoded.sib_index_reg,
            .scale = decoded.sib_scale,
            .has_base = decoded.sib_has_base,
            .base_reg = decoded.sib_base_reg,
            .rip_relative = decoded.rip_relative,
            .segment = decoded.segment,
        }, last_rip +| decoded.len, if (decoded.has_0x67) .bits32 else .bits64, .long64, true);
        target = process_impl_guest_memory.read64(self, source_address);
        source_label = "memory";
    }
    const current_rip = process_impl_lifecycle.guestContextField(self, "regs").*.rip;
    if (target != fetch_address and target != current_rip) return false;

    if (comptime !@import("builtin").is_test) {
        var source_text: [__process_guest_symbol_text_bytes]u8 = undefined;
        __process_log.err("PE64 INVALID WINDOWS CONTROL TRANSFER: target=0x{x} target_outside_guest_executable_backing=true transfer_rip=0x{x} ({s}) op={s} operand={s}:0x{x} loaded_target=0x{x} instruction_len={d} thread=0x{x} thread_id=0x{x} rsp=0x{x} return=0x{x} stack1=0x{x} gprs=[rax=0x{x},rbx=0x{x},rcx=0x{x},rdx=0x{x},rsi=0x{x},rdi=0x{x},rbp=0x{x},r8=0x{x},r9=0x{x},r10=0x{x},r11=0x{x},r12=0x{x},r13=0x{x},r14=0x{x},r15=0x{x}] bytes={any}", .{
            target,
            last_rip,
            process_impl_kernel_services.describeGuestAddressOrUnnamed(self, last_rip, &source_text),
            @tagName(decoded.op),
            source_label,
            source_address,
            target,
            decoded.len,
            process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            process_impl_lifecycle.currentWindowsThreadId(self),
            process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
            process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
            process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp +| 8),
            process_impl_lifecycle.guestContextField(self, "regs").*.rax,
            process_impl_lifecycle.guestContextField(self, "regs").*.rbx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rcx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdx,
            process_impl_lifecycle.guestContextField(self, "regs").*.rsi,
            process_impl_lifecycle.guestContextField(self, "regs").*.rdi,
            process_impl_lifecycle.guestContextField(self, "regs").*.rbp,
            process_impl_lifecycle.guestContextField(self, "regs").*.r8,
            process_impl_lifecycle.guestContextField(self, "regs").*.r9,
            process_impl_lifecycle.guestContextField(self, "regs").*.r10,
            process_impl_lifecycle.guestContextField(self, "regs").*.r11,
            process_impl_lifecycle.guestContextField(self, "regs").*.r12,
            process_impl_lifecycle.guestContextField(self, "regs").*.r13,
            process_impl_lifecycle.guestContextField(self, "regs").*.r14,
            process_impl_lifecycle.guestContextField(self, "regs").*.r15,
            bytes[0..@as(usize, decoded.len)],
        });
    }

    var direct_slots_checked: usize = 0;
    var changed_slots: usize = 0;
    var target_matches_iat = false;
    const direct_count = @min(self.windows_direct_stub_count, self.windows_stub_count);
    for (self.windows_stub_storage[0..direct_count]) |stub| {
        if (stub.iat_address == 0) continue;
        direct_slots_checked += 1;
        const actual = process_impl_guest_memory.read64(self, stub.iat_address);
        if (actual == target) target_matches_iat = true;
        if (actual == stub.address) continue;
        changed_slots += 1;
        if (changed_slots <= 8 and !@import("builtin").is_test) {
            __process_log.err("PE64 INVALID CONTROL TARGET IAT SAMPLE: {s}!{s} slot=0x{x} expected_stub=0x{x} actual=0x{x} target_match={} thread=0x{x} step={d}", .{
                stub.dll_name,
                stub.function_name,
                stub.iat_address,
                stub.address,
                actual,
                actual == target,
                process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                process_impl_lifecycle.observedExecutionSteps(self),
            });
        }
    }
    self.windows_iat_mismatches_at_fault = @intCast(changed_slots);
    if (comptime !@import("builtin").is_test) __process_log.err("PE64 INVALID CONTROL TARGET IAT AUDIT: direct_slots_checked={d} changed_slots={d} target_matches_slot={} target=0x{x}; changed IAT entries indicate a guest-memory overwrite, while intact slots with a wrong register value point to register/context corruption", .{
        direct_slots_checked,
        changed_slots,
        target_matches_iat,
        target,
    });
    process_impl_lifecycle.guestContextField(self, "decode_failure_is_invalid_control_target").* = true;
    return true;
}

pub inline fn resolveDecodedAddress(
    self: *ElfState,
    decoded: __process_DecodedInsn,
    decoded_segment: __process_x64_decoder.Segment,
) __process_DecodedInsn {
    var d = decoded;
    d.segment = decoded_segment;
    const addr_size: __process_Size = if (d.has_0x67) .bits32 else .bits64;
    const relative_control = switch (d.op) {
        .call_rel32, .jmp_rel8, .jcc_rel8, .jcc_rel32 => true,
        else => false,
    };
    if (!relative_control and !d.is_reg_form) {
        d.addr = __process_x64_decoder.resolveMemoryAddress(&process_impl_lifecycle.guestContextField(self, "regs").*, .{
            .displacement = d.addr,
            .has_index = d.sib_has_index,
            .index_reg = d.sib_index_reg,
            .scale = d.sib_scale,
            .has_base = d.sib_has_base,
            .base_reg = d.sib_base_reg,
            .rip_relative = d.rip_relative,
            .segment = d.segment,
        }, process_impl_lifecycle.guestContextField(self, "regs").*.rip +% d.len, addr_size, .long64, d.op != .lea_reg_mem);
    }
    return d;
}

pub fn decodeAt(self: *ElfState) ?__process_DecodedInsn {
    process_impl_lifecycle.guestContextField(self, "decode_failure_is_invalid_control_target").* = false;
    const fetch_address = process_impl_lifecycle.guestContextField(self, "regs").*.rip +% __process_x64_decoder.segmentBase(&process_impl_lifecycle.guestContextField(self, "regs").*, .cs, .long64);
    var bytes: []const u8 = undefined;
    var remaining: usize = 0;
    var mapped_code: ?__process_WindowsMappedCodeSlice = null;
    if (process_impl_guest_memory.addrToOffset(self, fetch_address)) |off| {
        remaining = self.mem.len - off;
        bytes = self.mem[off..];
    } else if (process_impl_guest_memory.windowsMappedCodeMemoryConst(self, fetch_address, __process_PE_MAX_INSTRUCTION_LENGTH)) |generated| {
        bytes = generated.bytes;
        remaining = bytes.len;
        mapped_code = generated;
        process_impl_block_jit.noteMappedCodeFetched(self, generated);
        self.windows_generated_code_fetches +|= 1;
        noteWindowsTitleCodeFetch(self, fetch_address);
        if (self.windows_runtime_enabled and self.windows_generated_code_fetches == 1) {
            __process_log.info("PE64 generated code execution: rip=0x{x} mapping={s} range=[0x{x},0x{x})", .{
                fetch_address,
                @tagName(generated.kind),
                generated.guest_base,
                generated.guest_base +| generated.length,
            });
        }
    } else {
        _ = reportInvalidWindowsControlTarget(self, fetch_address);
        if (self.windows_runtime_enabled) {
            __process_log.err("PE64 decode fetch outside guest image or mapped generated code: rip=0x{x} fetch=0x{x} mem=[0x{x},0x{x}) mem_len=0x{x} cs_base=0x{x} thread=0x{x} last_rip=0x{x} last_op={s} last_len={d} rsp=0x{x} stack0=0x{x} stack1=0x{x}", .{
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                fetch_address,
                self.mem_base,
                self.mem_base +| self.mem_size,
                self.mem.len,
                process_impl_lifecycle.guestContextField(self, "regs").*.segments.cs.base,
                process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
                process_impl_lifecycle.guestContextField(self, "last_instruction_rip").*,
                @tagName(process_impl_lifecycle.guestContextField(self, "last_decoded_op").*),
                process_impl_lifecycle.guestContextField(self, "last_decoded_len").*,
                process_impl_lifecycle.guestContextField(self, "regs").*.rsp,
                process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp),
                process_impl_guest_memory.read64(self, process_impl_lifecycle.guestContextField(self, "regs").*.rsp +| 8),
            });
        }
        return null;
    }
    var coordinated_instruction_bytes: [__process_PE_MAX_INSTRUCTION_LENGTH]u8 = undefined;
    if (remaining == 0) {
        if (self.windows_runtime_enabled) {
            __process_log.err("PE64 decode fetch at guest-image end: rip=0x{x} fetch=0x{x} off=0x{x} mem_len=0x{x} thread=0x{x}", .{
                process_impl_lifecycle.guestContextField(self, "regs").*.rip,
                fetch_address,
                process_impl_guest_memory.addrToOffset(self, fetch_address) orelse 0,
                self.mem.len,
                process_impl_lifecycle.guestContextField(self, "active_guest_thread").*,
            });
        }
        return null;
    }
    // PAUSE is the only instruction Xenia's hot guest spin loops must
    // interpret on every visit. Recognize its exact bytes before the
    // shared set lookup and decode machinery. The ordered comparison
    // forwards this executor's queued code writes and rejects a changed
    // opcode, just as the parallel decode-cache hit path does below.
    if (self.parallel_guest_execution and remaining >= 2 and
        __process_tso_memory.eqlCodeBytes(&[_]u8{ 0xF3, 0x90 }, bytes[0..2], coordinated_instruction_bytes[0..2]))
    {
        return .{ .op = .nop, .len = 2 };
    }
    const cache_set = __process_peDecodeCacheSetIndex(fetch_address);
    if (self.parallel_guest_execution) {
        // The private tier preserves the shared cache's exact-byte check,
        // which is the final guard for executable aliases and
        // self-modifying code; it compares without an address stripe
        // (`tso_memory.eqlCodeBytes`).
        const owner: *anyopaque = @ptrCast(self);
        const local_entries = __process_WorkerLocalDecodeCache.entriesFor(owner);
        const local_entry = &local_entries[cache_set & (__process_PE_DECODE_CACHE_LOCAL_ENTRIES - 1)];
        if (decodeCacheEntryHasIdentity(local_entry, fetch_address, mapped_code)) {
            const cached_len = @as(usize, local_entry.decoded.len);
            const same_source = cached_len != 0 and cached_len <= remaining and
                cached_len <= __process_PE_MAX_INSTRUCTION_LENGTH;
            if (same_source and __process_tso_memory.eqlCodeBytes(
                local_entry.bytes[0..cached_len],
                bytes[0..cached_len],
                coordinated_instruction_bytes[0..cached_len],
            )) {
                __process_WorkerLocalDecodeCache.noteHit(&self.decode_cache_worker_local_hits);
                return resolveDecodedAddress(self, local_entry.decoded, local_entry.segment);
            }
            if (same_source) local_entry.valid = false;
        }
    }
    const cache_index = __process_peDecodeCacheIndex(fetch_address);
    const shard_index = cache_set % __process_decode_cache_set_lock_count;
    const shard = &self.decode_cache_shards[shard_index];
    // Parallel executors share a striped set lock. The expanded stripe
    // table prevents unrelated sets from serializing, while each stripe
    // also owns the hot counters and LRU clock for its residents.
    const set_lock: ?*__process_concurrency.mutex.LeanMutex = if (self.parallel_guest_execution)
        &__ProcessInternals._decode_cache_set_locks().*[shard_index]
    else
        null;
    if (set_lock) |lock| lock.lock();
    defer if (set_lock) |lock| lock.unlock();
    var d: __process_DecodedInsn = .{};
    var decoded_segment: __process_x64_decoder.Segment = .ds;
    var cache_entry: ?*__process_DecodeCacheEntry = null;
    var rearmed = false;
    var victim_restored = false;
    var victim_rearmed = false;
    var stale_entry: ?*__process_DecodeCacheEntry = null;
    var vacant_entry: ?*__process_DecodeCacheEntry = null;
    var oldest_entry: ?*__process_DecodeCacheEntry = null;
    var oldest_use: u64 = __process_std.math.maxInt(u64);
    var resident_addresses: [__process_PE_DECODE_CACHE_WAYS]u64 = @splat(0);
    var resident_count: usize = 0;

    // Only an image fetch has an image generation; a mapped-code fetch
    // carries its mapping's generation and never consults this table.
    const resident_set = self.decode_cache[cache_index..][0..__process_PE_DECODE_CACHE_WAYS];
    for (resident_set) |*candidate| {
        if (!candidate.valid) {
            if (vacant_entry == null) vacant_entry = candidate;
            continue;
        }
        if (resident_count < resident_addresses.len) {
            resident_addresses[resident_count] = candidate.fetch_address;
            resident_count += 1;
        }
        if (oldest_entry == null or candidate.last_used < oldest_use) {
            oldest_entry = candidate;
            oldest_use = candidate.last_used;
        }
        if (!decodeCacheEntryHasIdentity(candidate, fetch_address, mapped_code)) continue;

        const cached_len = @as(usize, candidate.decoded.len);
        const same_source = cached_len != 0 and cached_len <= remaining and
            cached_len <= __process_PE_MAX_INSTRUCTION_LENGTH;
        const image_generation: ?u64 = if (mapped_code == null and same_source and !self.parallel_guest_execution)
            process_impl_guest_memory.windowsImageCodeGenerationFor(self, fetch_address, cached_len)
        else
            null;
        const parallel_bytes_match = same_source and self.parallel_guest_execution and
            __process_tso_memory.eqlCodeBytes(candidate.bytes[0..cached_len], bytes[0..cached_len], coordinated_instruction_bytes[0..cached_len]);
        const cache_hit = same_source and (if (self.parallel_guest_execution)
            parallel_bytes_match
        else if (mapped_code) |generated|
            candidate.source_generation == generated.generation
        else if (image_generation) |generation|
            candidate.source_generation == generation
        else
            __process_std.mem.eql(u8, candidate.bytes[0..cached_len], bytes[0..cached_len]));
        if (cache_hit) {
            cache_entry = candidate;
            d = candidate.decoded;
            decoded_segment = candidate.segment;
            break;
        }

        // A mapping-wide generation can move because another JIT
        // function was emitted. Re-check the old bytes before paying for
        // a fresh decode: most such changes are unrelated to this entry,
        // so the old decode can simply be re-armed for the new generation.
        const bytes_match = same_source and (if (self.parallel_guest_execution)
            parallel_bytes_match
        else
            __process_std.mem.eql(u8, candidate.bytes[0..cached_len], bytes[0..cached_len]));
        if (bytes_match) {
            cache_entry = candidate;
            rearmed = true;
            d = candidate.decoded;
            decoded_segment = candidate.segment;
            if (mapped_code) |generated| candidate.source_generation = generated.generation;
            if (mapped_code == null and !self.parallel_guest_execution) {
                if (process_impl_guest_memory.windowsImageCodeGenerationFor(self, fetch_address, cached_len)) |generation| {
                    candidate.source_generation = generation;
                }
            }
            break;
        }
        // The same source address is resident but its bytes no longer
        // match. Preserve that slot for the refill instead of creating a
        // duplicate copy in a vacant way.
        if (stale_entry == null) stale_entry = candidate;
    }

    if (cache_entry == null) {
        // The overwhelmingly common path above compares backing bytes
        // under their shared access stripe without copying them to a
        // temporary. Only a miss needs a stable byte snapshot for victim
        // validation or a fresh decode.
        if (self.parallel_guest_execution) {
            const count = @min(remaining, coordinated_instruction_bytes.len);
            process_impl_guest_memory.snapshotGuestBacking(self, coordinated_instruction_bytes[0..count], bytes[0..count]);
            bytes = coordinated_instruction_bytes[0..count];
            remaining = count;
        }
        // A primary miss is not necessarily a fresh decode. A recent
        // conflict may have displaced this exact instruction into the
        // bounded victim bank. Restore it into the same primary set so
        // the next access is back on the normal fast path.
        // The victim bank and the miss diagnostics are shared across sets:
        // their own lock, always taken after a set lock.
        if (set_lock != null) __ProcessInternals._decode_cache_miss_mutex().*.lock();
        defer if (set_lock != null) __ProcessInternals._decode_cache_miss_mutex().*.unlock();
        if (findDecodeCacheVictim(self, fetch_address, bytes, remaining, mapped_code, shard)) |victim| {
            const selected_entry = stale_entry orelse vacant_entry orelse oldest_entry;
            if (selected_entry) |selected| {
                selected.* = victim.entry.*;
                victim.entry.valid = false;
                cache_entry = selected;
                d = selected.decoded;
                decoded_segment = selected.segment;
                victim_restored = true;
                victim_rearmed = victim.rearmed;
            }
        }
    }

    if (cache_entry) |entry| {
        if (victim_restored) shard.counters.victim_hits +|= 1;
        if (rearmed or victim_rearmed) {
            shard.counters.rearms +|= 1;
        } else {
            shard.counters.hits +|= 1;
        }
        touchDecodeCachePrimaryEntry(entry, shard);
    } else {
        shard.counters.misses +|= 1;
        const selected_entry = stale_entry orelse vacant_entry orelse oldest_entry orelse return null;
        const cause: __process_DecodeCacheMissCause = if (stale_entry != null)
            .stale_bytes
        else if (vacant_entry != null)
            .vacant_fill
        else
            .capacity_conflict;
        if (cause == .capacity_conflict) shard.counters.replacements +|= 1;
        {
            if (set_lock != null) __ProcessInternals._decode_cache_miss_mutex().*.lock();
            defer if (set_lock != null) __ProcessInternals._decode_cache_miss_mutex().*.unlock();
            if (cause == .capacity_conflict) saveDecodeCacheVictim(self, selected_entry, shard);
            noteDecodeCacheMiss(self, cause, fetch_address, cache_set, resident_addresses, resident_count, mapped_code, shard);
        }
        if (process_impl_lifecycle.isTerminated(self)) return null;

        d = __process_decodeInsn(bytes);
        const decoded_len = @as(usize, d.len);
        if (decoded_len != 0 and decoded_len <= remaining and decoded_len <= __process_PE_MAX_INSTRUCTION_LENGTH) {
            const prefixes = __process_x64_decoder.decodeLegacyPrefixes(bytes);
            const base: ?__process_RegId = if (d.sib_has_base) d.sib_base_reg else null;
            decoded_segment = __process_x64_decoder.selectSegment(.explicit_data, base, prefixes.segment_override);
            selected_entry.* = .{
                .valid = true,
                .fetch_address = fetch_address,
                .mapped_source = mapped_code != null,
                .source_kind = if (mapped_code) |generated| generated.kind else .memory_view,
                .source_index = if (mapped_code) |generated| generated.source_index else 0,
                .source_generation = if (self.parallel_guest_execution)
                    0
                else if (mapped_code) |generated|
                    generated.generation
                else if (process_impl_guest_memory.windowsImageCodeGenerationFor(self, fetch_address, decoded_len)) |generation|
                    generation
                else
                    0,
                .segment = decoded_segment,
                .decoded = d,
            };
            @memcpy(selected_entry.bytes[0..decoded_len], bytes[0..decoded_len]);
            touchDecodeCachePrimaryEntry(selected_entry, shard);
            cache_entry = selected_entry;
        }
    }
    // The shared decoder records the address-size bit in `d`, but the
    // executor still needs the raw segment override to select DS versus
    // SS for an explicit memory operand. This was computed on a cache
    // fill and carried by the entry on a hit.
    const addr_size: __process_Size = if (d.has_0x67) .bits32 else .bits64;
    d.segment = decoded_segment;
    // Relative control instructions keep their signed displacement in
    // `addr` (and `imm`) for highway.relativeControl.  They are marked
    // rip_relative by the legacy decoder, but that flag describes the
    // encoding rather than a data-memory operand.  Resolving them here
    // would turn the displacement into an absolute address, then the
    // executor would add RIP a second time.  Only data-memory operands
    // need effective-address resolution at this stage.
    const relative_control = switch (d.op) {
        .call_rel32, .jmp_rel8, .jcc_rel8, .jcc_rel32 => true,
        else => false,
    };
    // Register-form instructions never consume d.addr.  The decoder
    // still carries the ModRM displacement field for a uniform decoded
    // shape, but resolving it here needlessly reads live segment/base
    // state on the overwhelmingly common register path.  Memory forms,
    // including LEA and absolute disp-only operands, retain the full
    // effective-address calculation.
    if (!relative_control and !d.is_reg_form) {
        d.addr = __process_x64_decoder.resolveMemoryAddress(&process_impl_lifecycle.guestContextField(self, "regs").*, .{
            .displacement = d.addr,
            .has_index = d.sib_has_index,
            .index_reg = d.sib_index_reg,
            .scale = d.sib_scale,
            .has_base = d.sib_has_base,
            .base_reg = d.sib_base_reg,
            .rip_relative = d.rip_relative,
            .segment = d.segment,
        }, process_impl_lifecycle.guestContextField(self, "regs").*.rip +% d.len, addr_size, .long64, d.op != .lea_reg_mem);
    }
    if (self.parallel_guest_execution) {
        if (cache_entry) |entry| {
            if (entry.valid and entry.fetch_address == fetch_address and entry.decoded.len != 0) {
                const owner: *anyopaque = @ptrCast(self);
                const local_entries = __process_WorkerLocalDecodeCache.entriesFor(owner);
                local_entries[cache_set & (__process_PE_DECODE_CACHE_LOCAL_ENTRIES - 1)] = entry.*;
            }
        }
    }
    return d;
}

pub fn advanceWindowsGuestClock(self: *ElfState) void {
    advanceWindowsGuestClockIn(self, process_impl_lifecycle.guestContextRef(self));
}

pub fn advanceWindowsGuestClockIn(self: *ElfState, ctx: __process_GuestContextRef) void {
    if (self.parallel_guest_execution and self.guest_clock.source == .host_monotonic) {
        const sample_steps = ctx.field("guest_clock_sample_steps");
        sample_steps.* +|= 1;
        if (sample_steps.* < __process_WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE) return;
        sample_steps.* = 0;
        sampleWindowsGuestClockIfFree(self);
        return;
    }
    self.guest_clock_mutex.lock();
    const prior_ticks = self.guest_clock.ticks;
    defer {
        if (self.guest_clock.ticks != prior_ticks) process_impl_lifecycle.publishWindowsGuestClockTicks(self);
        self.guest_clock_mutex.unlock();
    }
    // The host clock is read here rather than inside `guest_clock.zig` so
    // that file has no syscall in it and stays testable without one. On
    // the strided path the read happens every 512 steps; the branch that
    // decides is one predictable compare.
    if (self.guest_clock.source == .retired_instructions) {
        self.guest_clock.advance(0);
        return;
    }
    self.guest_clock.stride +|= 1;
    if (self.guest_clock.stride < __process_WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE) return;
    self.guest_clock.refresh(__process_monotonicNanoseconds());
}

pub fn sampleWindowsGuestClockIfFree(self: *ElfState) void {
    if (!self.guest_clock_mutex.tryLock()) return;
    const prior_ticks = self.guest_clock.ticks;
    defer {
        if (self.guest_clock.ticks != prior_ticks) process_impl_lifecycle.publishWindowsGuestClockTicks(self);
        self.guest_clock_mutex.unlock();
    }
    self.guest_clock.refresh(__process_monotonicNanoseconds());
}

pub fn refreshWindowsGuestClock(self: *ElfState) void {
    self.guest_clock_mutex.lock();
    const prior_ticks = self.guest_clock.ticks;
    defer {
        if (self.guest_clock.ticks != prior_ticks) process_impl_lifecycle.publishWindowsGuestClockTicks(self);
        self.guest_clock_mutex.unlock();
    }
    self.guest_clock.refresh(__process_monotonicNanoseconds());
}

pub fn advanceWindowsGuestClockBy(self: *ElfState, count: u64) void {
    if (count == 0) return;
    if (self.parallel_guest_execution and self.guest_clock.source == .host_monotonic) {
        const sample_steps = process_impl_lifecycle.guestContextField(self, "guest_clock_sample_steps");
        sample_steps.* +|= (count + __process_WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP - 1) / __process_WINDOWS_GUEST_CLOCK_TRANSLATED_PER_STEP;
        if (sample_steps.* < __process_WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE) return;
        sample_steps.* = 0;
        sampleWindowsGuestClockIfFree(self);
        return;
    }
    self.guest_clock_mutex.lock();
    const prior_ticks = self.guest_clock.ticks;
    defer {
        if (self.guest_clock.ticks != prior_ticks) process_impl_lifecycle.publishWindowsGuestClockTicks(self);
        self.guest_clock_mutex.unlock();
    }
    if (self.guest_clock.source == .retired_instructions) {
        self.guest_clock.advanceRetired(count);
        return;
    }
    self.guest_clock.stride +|= count;
    if (self.guest_clock.stride < __process_WINDOWS_GUEST_CLOCK_SAMPLE_STRIDE) return;
    self.guest_clock.refresh(__process_monotonicNanoseconds());
}
