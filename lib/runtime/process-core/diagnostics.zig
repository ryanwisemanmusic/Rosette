//! Diagnostics summary and exit-report functions extracted from process.zig.
//! Uses `anytype` for the `self` parameter (inferred as `*MachOState` at call sites).

const std = @import("std");
const x64_decoder = @import("x64_decoder");
const Size = x64_decoder.OperandSize;
const execution_helpers = @import("macho_core").execution_helpers;
const maskForSize = execution_helpers.maskForSize;
const signBitForSize = execution_helpers.signBitForSize;
const exit_diagnostics = @import("exit_diagnostics");
const semantic_fault_classifier = @import("diagnostics").semantic_fault_classifier;
const macho_log = @import("dyld").event_log;
const machoCapturePrint = macho_log.machoCapturePrint;
const primitiveCapturePrint = macho_log.primitiveCapturePrint;
const constants = @import("macho_core").constants;
const TraceEntry = @import("macho_core").types.TraceEntry;
const TRACE_BUFFER_LEN = constants.TRACE_BUFFER_LEN;
const MEMORY_TRACE_BUFFER_LEN = constants.MEMORY_TRACE_BUFFER_LEN;
const IMPORT_TRACE_BUFFER_LEN = constants.IMPORT_TRACE_BUFFER_LEN;
const IMPORT_ROUTE_CACHE_SIZE = constants.IMPORT_ROUTE_CACHE_SIZE;

/// Report the window every guest-address decision was actually made against.
///
/// This predicate had two owners: the model, derived from observed mappings,
/// and a free function over the bootstrap constants that every decision site
/// called. The model has since been made the single owner — but a derived
/// answer that nothing can audit is no better than an asserted one, so the run
/// states which window it used, where that window came from, and whether it
/// still matches the bootstrap range it replaced.
///
/// `source=bootstrap_default` at the end of a run that mapped guest memory is
/// itself the finding: it means every observation was rejected, and the model
/// answered from a constant all run. That is exactly what happened while the
/// backend mapping route was not reporting to the model at all.
fn logGuestWindowContract(self: anytype) void {
    const model = &self.guest_address_space;
    const guest_address_space_lib = @import("guest_address_space");
    const bootstrap_base: u64 = guest_address_space_lib.window.bootstrap_base;
    const bootstrap_end: u64 = guest_address_space_lib.window.bootstrap_end;
    const agrees = model.base == bootstrap_base and model.end == bootstrap_end;
    machoCapturePrint(
        "macho-processor: guest window contract: window=[0x{x},0x{x}) source={s} derived={} observed_regions={d} ignored_observations={d} bootstrap=[0x{x},0x{x}) matches_bootstrap={}; every guest-address decision this run used this window — {s}\n",
        .{
            model.base,
            model.end,
            @tagName(model.source),
            model.source.derived(),
            model.region_count,
            model.ignored_observations,
            bootstrap_base,
            bootstrap_end,
            agrees,
            if (!model.source.derived())
                "NOTHING was derived: every observation was rejected as non-canonical, too small, or executable, so the window is a constant. If the run mapped guest RAM, a mapping route is not reporting to the model"
            else if (agrees)
                "derived from observation and identical to the bootstrap range, so the constant it replaced was correct for this workload"
            else
                "derived from observation and DIFFERENT from the bootstrap range; recoveries gated on guest-address membership classified against the observed layout, not the constant",
        },
    );
}

pub fn logDecodeCacheSummary(self: anytype) void {
    const total = self.decode_cache_hits + self.decode_cache_misses;
    const hit_percent = if (total == 0) 0 else self.decode_cache_hits * 100 / total;
    machoCapturePrint(
        "macho-processor: decode cache: entries={d} hits={d} misses={d} hit_rate={d}% stale_byte_rejections={d} code_generation={d}\n",
        .{ self.decode_cache.len, self.decode_cache_hits, self.decode_cache_misses, hit_percent, self.decode_cache_stale_rejections, self.code_generation },
    );
}

pub fn logPerformanceAccelerationSummary(self: anytype) void {
    const total = self.import_route_cache_hits + self.import_route_cache_misses;
    const hit_percent = if (total == 0) 0 else self.import_route_cache_hits * 100 / total;
    // A hit whose route is `.legacy`/`.strtoul` re-enters the slow path, so the
    // lookup matched and nothing was saved. The effective rate is the one that
    // describes work avoided, and it is the number worth optimising against.
    const effective_hits = self.import_route_cache_hits -| self.import_route_cache_slow_hits;
    const attempts = total + self.import_route_cache_fallbacks;
    const effective_percent = if (attempts == 0) 0 else effective_hits * 100 / attempts;
    machoCapturePrint(
        "macho-processor: import route cache: entries={d} hits={d} misses={d} hit_rate={d}% collisions={d} fallbacks={d}\n",
        .{ IMPORT_ROUTE_CACHE_SIZE, self.import_route_cache_hits, self.import_route_cache_misses, hit_percent, self.import_route_cache_collisions, self.import_route_cache_fallbacks },
    );
    if (comptime @hasField(@TypeOf(self.*), "import_route_cache_slow_hits")) {
        machoCapturePrint(
            "macho-processor: import route cache effectiveness: dispatches={d} slow_path_avoided={d} ({d}%) hits_that_re_entered_the_slow_path={d} fallbacks={d}; the headline hit rate counts lookups that matched, not work avoided — a `.legacy` hit runs the whole symbol chain anyway\n",
            .{ attempts, effective_hits, effective_percent, self.import_route_cache_slow_hits, self.import_route_cache_fallbacks },
        );
    }
    if (comptime @hasField(@TypeOf(self.*), "import_route_fallbacks")) {
        if (self.import_route_cache_fallbacks != 0) {
            const RouteEnum = @import("macho_core").types.ImportRoute;
            inline for (@typeInfo(RouteEnum).@"enum".fields) |field| {
                const count = self.import_route_fallbacks[field.value];
                if (count != 0) {
                    machoCapturePrint(
                        "  route fallback: route={s} count={d}; this route was cached for a stub and then declined it, so its applicability is not a function of the stub address\n",
                        .{ field.name, count },
                    );
                }
            }
        }
    }
    machoCapturePrint(
        "macho-processor: bulk construction acceleration: page_entry_runs={d} bytes={d}\n",
        .{ self.page_entry_bulk_initializations, self.page_entry_bulk_bytes },
    );
    if (self.lazy_import_direct_dispatches != 0) {
        machoCapturePrint(
            "macho-processor: lazy import safety: typed_direct_dispatches={d} dyld_stub_binder_entries=0\n",
            .{self.lazy_import_direct_dispatches},
        );
    }
    if (self.patch_db_empty_array_recoveries != 0) {
        machoCapturePrint(
            "macho-processor: PatchDB empty-patch compatibility: recoveries={d}\n",
            .{self.patch_db_empty_array_recoveries},
        );
    }
    if (comptime @hasField(@TypeOf(self.*), "generated_endian_contract")) {
        if (self.generated_endian_contract.recoveries != 0) {
            machoCapturePrint(
                "macho-processor: generated endian contract: witnessed_repairs={d}\n",
                .{self.generated_endian_contract.recoveries},
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "generated_null_scalar_read")) {
        if (self.generated_null_scalar_read.recoveries != 0) {
            machoCapturePrint(
                "macho-processor: generated null scalar reads: zero_fill_recoveries={d} (JIT cvar/global reads satisfied as zero)\n",
                .{self.generated_null_scalar_read.recoveries},
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "gpu_bootstrap")) {
        const gpu = @import("gpu");
        const frontier = self.gpu_bootstrap.frontier();
        if (frontier.step) |blocked| {
            machoCapturePrint(
                "macho-processor: gpu bootstrap frontier: reached={d}/{d} first_missing={s} precondition_met={} blocked_by={s} out_of_order={d}; {s}\n",
                .{
                    frontier.reached,
                    gpu.bootstrap.step_count,
                    blocked.label(),
                    frontier.precondition_met,
                    if (frontier.blocked_by) |required| required.label() else "<none>",
                    self.gpu_bootstrap.out_of_order,
                    blocked.guidance(),
                },
            );
            inline for (@typeInfo(gpu.Step).@"enum".fields) |field| {
                const step: gpu.Step = @enumFromInt(field.value);
                const entry = self.gpu_bootstrap.observations[field.value];
                machoCapturePrint(
                    "  gpu step {s}: observed={} calls={d} first_step={d}\n",
                    .{ step.label(), entry.seen, entry.count, entry.first_step },
                );
            }
        } else if (self.gpu_bootstrap.observations[0].seen) {
            machoCapturePrint(
                "macho-processor: gpu bootstrap frontier: complete ({d}/{d} steps observed, out_of_order={d}); the guest drove the whole bootstrap, so any remaining absence of output is downstream of command submission\n",
                .{ frontier.reached, gpu.bootstrap.step_count, self.gpu_bootstrap.out_of_order },
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "dispatch_census")) {
        if (self.dispatch_census.observations != 0) {
            const coverage = self.dispatch_census.coverage();
            machoCapturePrint(
                "macho-processor: dispatch coverage: distinct_sites={d} traversed_always={d} sometimes={d} never={d} | observations={d} passes={d} halts={d} overflow_sites={d}. This is how much of the generated code the bounded machine could get through. `never` is the size of the gap; `sometimes` is more informative than either, because the same instruction traversing under one register state and not another makes the difference between them the defect\n",
                .{
                    coverage.sites,
                    coverage.clean,
                    coverage.mixed,
                    coverage.halting,
                    self.dispatch_census.observations,
                    self.dispatch_census.traversals,
                    self.dispatch_census.halts,
                    self.dispatch_census.overflow_sites,
                },
            );
            const Family = @import("dispatch_recovery").Family;
            inline for (@typeInfo(Family).@"enum".fields) |field| {
                const count = self.dispatch_census.by_family[field.value];
                if (count != 0) {
                    machoCapturePrint(
                        "  traversals by family: {s}={d}\n",
                        .{ field.name, count },
                    );
                }
            }
            var index: usize = 0;
            while (index < self.dispatch_census.count) : (index += 1) {
                const site = self.dispatch_census.sites[index];
                if (site.traversals != 0 and site.halts == 0) continue;
                machoCapturePrint(
                    "  site rip=0x{x} block=0x{x} reached={d} passes={d} halts={d} last_family={s} last_halt_reason={d}\n",
                    .{ site.rip, site.block_start, site.observations, site.traversals, site.halts, @tagName(site.last_family), site.last_halt_reason },
                );
            }
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "generated_byte_order_repair")) {
        if (self.generated_byte_order_repair.recoveries != 0) {
            machoCapturePrint(
                "macho-processor: byte-reversed base registers repaired: {d}. Each was a guest address whose eight bytes were never converted from big-endian, leaving zero in the low half so that every 32-bit addressing form computed a null. These faults were NOT near-null casualties and did not enter that machinery; without the repair each would have halted the bounded machine at a site whose pointer was in fact present\n",
                .{self.generated_byte_order_repair.recoveries},
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "generated_missed_guest_return")) {
        if (self.generated_missed_guest_return.recoveries != 0) {
            machoCapturePrint(
                "macho-processor: missed guest returns recovered: {d}. Each one was a guest RETURN that executed as an indirect dispatch because the target register held the guest return address with its bytes reversed, defeating Xenia's CALL_POSSIBLE_RETURN compare. The recovery resumes the guest caller, but the reversal is the defect: a guest code address reached generated code in host byte order, so a store of that address into guest memory skipped its big-endian conversion. Every CALL_POSSIBLE_RETURN-guarded dispatch is exposed to it\n",
                .{self.generated_missed_guest_return.recoveries},
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "generated_null_indirect")) {
        if (self.generated_null_indirect.recoveries != 0) {
            machoCapturePrint(
                "macho-processor: generated null indirect transfers: skipped_tail_calls={d} (JIT indirection misses; tail dispatches returned to host caller)\n",
                .{self.generated_null_indirect.recoveries},
            );
            // A skipped *tail* call is not a skipped instruction. The dispatch
            // was the last thing the generated function was going to do, so
            // returning to the host caller abandons everything the callee would
            // have done — and the caller sees a normal return, so nothing
            // downstream reports an error. A subsystem that never initialises
            // because its entry point was skipped looks exactly like a
            // subsystem the guest chose not to use, and only this line
            // distinguishes them.
            machoCapturePrint(
                "macho-processor: guest work abandoned: {d} tail dispatch(es) were skipped rather than resolved. Each one returned a generated frame to its host caller WITHOUT running the guest function it was dispatching to, and the caller cannot tell the difference from a normal return. Any guest-side initialisation behind those calls did not happen and will be reported downstream as \"never requested\" rather than as a failure. Resolve the dispatch — see the `null transfer table probe` lines for whether the table entry was missing or the whole table was unfilled — before treating any dependent subsystem's inactivity as a separate defect\n",
                .{self.generated_null_indirect.recoveries},
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "generated_guest_dispatch")) {
        if (self.generated_guest_dispatch.recoveries != 0) {
            machoCapturePrint(
                "macho-processor: generated guest dispatches: skipped={d} (unpatched Xenia indirection sentinels returned to host caller)\n",
                .{self.generated_guest_dispatch.recoveries},
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "generated_dispatch_frame_return")) {
        if (self.generated_dispatch_frame_return.recoveries != 0) {
            machoCapturePrint(
                "macho-processor: generated dispatch frame returns: {d} (tail-dispatch misses returned to host caller via rbp frame, leave;ret semantics)\n",
                .{self.generated_dispatch_frame_return.recoveries},
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "imgui_text_ex_noops")) {
        if (self.imgui_text_ex_noops != 0) {
            machoCapturePrint(
                "macho-processor: ImGui TextEx compatibility: no-op_calls={d} (Xenia headless renderer boundary; exact symbol interception)\n",
                .{self.imgui_text_ex_noops},
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "bounded_dispatch")) {
        if (self.bounded_dispatch.observations != 0) {
            machoCapturePrint(
                "macho-processor: bounded dispatch FST: observations={d} proven_redirects={d} assumed_continuations={d} (of which after_discarded_backing={d}) rejections={d}. Proven redirects follow from evidence; assumed continuations do not — each one is a point where the guest's dispatch target was provably zero and the run continued anyway so the next failure could be observed. A non-zero assumed count means guest state after those points is Rosette's construction. The after_discarded_backing subset is weaker still: there the field's storage was replaced by the runtime, so its zero is not evidence that the guest never wrote it. Set ROSETTE_MACHO_STRICT_DISPATCH=1 to fail closed instead\n",
                .{ self.bounded_dispatch.observations, self.bounded_dispatch.redirects, self.bounded_dispatch.assumed_continuations, self.bounded_dispatch.assumed_after_discarded_backing, self.bounded_dispatch.rejections },
            );
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "guest_lifetime")) {
        if (self.guest_lifetime.events != 0) {
            machoCapturePrint(
                "macho-processor: guest range lifetime: discards={d} tracked_ranges={d} evictions={d} consulted(hits/misses)={d}/{d}. Each discard is a guest range whose backing Rosette replaced, unmapped or re-homed; write provenance, vtable identity and decoded bytes for it were retired at that point. A hit means a fault-time diagnosis asked about an address in one of these ranges — an absence of evidence there is Rosette's, not the guest's\n",
                .{
                    self.guest_lifetime.events,
                    self.guest_lifetime.count,
                    self.guest_lifetime.evictions,
                    self.guest_lifetime.hits,
                    self.guest_lifetime.misses,
                },
            );
            var index: usize = 0;
            while (index < self.guest_lifetime.count) : (index += 1) {
                const record = self.guest_lifetime.entries[index];
                machoCapturePrint(
                    "  discarded range: base=0x{x} length={d} reason={s} discards={d} last_step={d}\n",
                    .{ record.base, record.size, @tagName(record.reason), record.generation, record.step },
                );
            }
        }
    }
    if (comptime @hasField(@TypeOf(self.*), "guest_address_space")) {
        logGuestWindowContract(self);
    }
    // Loop-guard reporting now belongs to each family's own ledger; the shared
    // `consecutive_dispatch_recoveries` field it read no longer exists.
    if (comptime @hasField(@TypeOf(self.*), "bounded_dispatch_recoveries")) {
        if (self.bounded_dispatch_recoveries.consecutive > 1) {
            machoCapturePrint(
                "macho-processor: bounded dispatch recoveries: {d} total, {d} consecutive at rip=0x{x} (limit {d})\n",
                .{
                    self.bounded_dispatch_recoveries.recoveries,
                    self.bounded_dispatch_recoveries.consecutive,
                    self.bounded_dispatch_recoveries.last_site,
                    @import("ownership").ledger.Ledger.consecutive_limit,
                },
            );
        }
    }
    if (self.libcxx_string_substr_fast_paths != 0 or self.profile_host_preflight_checks != 0) {
        machoCapturePrint(
            "macho-processor: libc++ path slicing: substr_fast_paths={d} profile_host_preflights={d}\n",
            .{ self.libcxx_string_substr_fast_paths, self.profile_host_preflight_checks },
        );
    }
    if (self.opaque_destructor_quarantines != 0) {
        machoCapturePrint(
            "macho-processor: opaque lifetime safety: destructor_quarantines={d}; only registered opaque identities with validated caller frames were skipped\n",
            .{self.opaque_destructor_quarantines},
        );
    }
    if (self.profile_account_flow.attempts != 0) {
        machoCapturePrint(
            "macho-processor: profile Account lifecycle: attempts={d} successes={d} failures={d} active={} final_stage={s} last_xuid={x:0>16} last_bytes_read={d}/{d}\n",
            .{ self.profile_account_flow.attempts, self.profile_account_flow.successes, self.profile_account_flow.failures, self.profile_account_flow.active, @tagName(self.profile_account_flow.stage), self.profile_account_flow.xuid, self.profile_account_flow.bytes_read, self.profile_account_flow.requested_bytes },
        );
    }
    if (self.atomic_cmpxchg.operations != 0) {
        machoCapturePrint(
            "macho-processor: atomic outcomes: cmpxchg(operations/matches/mismatches)={d}/{d}/{d}; mismatches are architectural outcomes, not runtime failures\n",
            .{ self.atomic_cmpxchg.operations, self.atomic_cmpxchg.matches, self.atomic_cmpxchg.mismatches },
        );
    }

    if (self.sha1_tracer.initial_report_done) {
        machoCapturePrint(
            "macho-processor: SHA1 hash verification: hot_function_rip=0x{x} this=0x{x} data=0x{x} length={d} last_block_index={d} last_byte_count={d} step_first_detected={d}\n",
            .{
                self.sha1_tracer.hot_function_rip,
                self.sha1_tracer.sha1_this_ptr,
                self.sha1_tracer.sha1_data_ptr,
                self.sha1_tracer.sha1_byte_len,
                self.sha1_tracer.last_block_index,
                self.sha1_tracer.last_byte_count,
                self.sha1_tracer.detected_at_step,
            },
        );
        machoCapturePrint(
            "macho-processor: SHA1 processBytes summary: entry_count={d} repeat_count={d} repeat_detected={} last_data=0x{x} last_length={d}\n",
            .{
                self.sha1_tracer.process_bytes_entry_count,
                self.sha1_tracer.pb_repeat_count,
                self.sha1_tracer.pb_repeat_detected,
                self.sha1_tracer.pb_data_ptr,
                self.sha1_tracer.pb_byte_len,
            },
        );
        if (self.guest_assertion_count == 0) {
            machoCapturePrint(
                "macho-processor: SHA1 progress: no assertion recovery or guest assertion was observed while the hash loop advanced\n",
                .{},
            );
        }
    }

    if (self.guest_assertion_count == 0) {
        machoCapturePrint(
            "macho-processor: runtime invariant check: PASS — cmpxchg operations={d} matches={d} mismatches={d}; no guest assertion\n",
            .{ self.atomic_cmpxchg.operations, self.atomic_cmpxchg.matches, self.atomic_cmpxchg.mismatches },
        );
    } else {
        machoCapturePrint(
            "macho-processor: runtime invariant check: FAIL — guest_assertions={d}; cmpxchg mismatches={d} are reported only as context\n",
            .{ self.guest_assertion_count, self.atomic_cmpxchg.mismatches },
        );
    }
    self.diagnostic_throttler.logSummary();
    logSharedControlBlockSummary(self);
}

pub fn logSharedControlBlockSummary(self: anytype) void {
    if (self.libcpp_shared_control_blocks.candidates == 0) return;
    machoCapturePrint(
        "macho-processor: libc++ shared control-block robustness: candidates={d} verified_vptr_restorations={d} rejected={d}\n",
        .{
            self.libcpp_shared_control_blocks.candidates,
            self.libcpp_shared_control_blocks.recoveries,
            self.libcpp_shared_control_blocks.rejected,
        },
    );
}

pub fn logExitDiagnostics(self: anytype) void {
    const reason: exit_diagnostics.TerminationReason = exit_diagnostics.reasonFromValue(self.termination_reason);
    const attribution = exit_diagnostics.attribute(.{
        .reason = reason,
        .faulted = self.faulted,
        .unresolved_import_calls = self.unresolved_import_count,
    });
    var report = exit_diagnostics.ExitReport{
        .exit_code = self.exit_code,
        .reason = reason,
        .faulted = self.faulted,
        .rip = self.regs.rip,
        .regs = .{
            .rax = self.regs.rax,
            .rbx = self.regs.rbx,
            .rcx = self.regs.rcx,
            .rdx = self.regs.rdx,
            .rsi = self.regs.rsi,
            .rdi = self.regs.rdi,
            .rbp = self.regs.rbp,
            .rsp = self.regs.rsp,
            .r8 = self.regs.r8,
            .r9 = self.regs.r9,
            .r10 = self.regs.r10,
            .r11 = self.regs.r11,
            .r12 = self.regs.r12,
            .r13 = self.regs.r13,
            .r14 = self.regs.r14,
            .r15 = self.regs.r15,
        },
        .unresolved_import_calls = self.unresolved_import_count,
        .attribution = attribution,
        .execution_authoritative = attribution.authority == .authoritative,
        .control_transfer_failure = self.terminal_control_transfer,
        .memory_access_failure = self.terminal_memory_failure,
        .runtime_context = .{
            .phase = @tagName(self.startup.phase),
            .steps = self.executed_steps,
            .phase_start_step = self.startup.phase_start_step,
            .initializer = if (self.initializer_resolver.current()) |initializer| initializer.symbol else "",
        },
    };

    const terminal_in_generated_code = self.sparse_memory.isExecutable(self.regs.rip, 1);
    if (self.isExecutableAddress(self.regs.rip) and !terminal_in_generated_code) {
        if (self.metadata.nearestSymbol(self.regs.rip)) |symbol| {
            report.terminal_symbol = .{
                .address = symbol.address,
                .symbol = symbol.name,
                .symbol_offset = symbol.offset,
            };
        }
    }

    if (self.terminal_memory_failure) |failure| {
        const instruction_in_generated_code = self.sparse_memory.isExecutable(failure.instruction_address, 1);
        const terminal_symbol = if (instruction_in_generated_code)
            null
        else
            self.metadata.nearestSymbol(failure.instruction_address);
        const symbol_name = if (terminal_symbol) |symbol| symbol.name else "";
        const fault_policy = self.pointer_firewall.policyAt(failure.address);
        var vtable_header_mapped = true;
        var typeinfo_mapped = true;
        if (self.guestMemoryConst(self.regs.rdi, 8) != null) {
            const vptr = self.read64(self.regs.rdi);
            if (vptr == 0 or vptr < 16 or self.guestMemoryConst(vptr - 16, 16) == null) {
                vtable_header_mapped = false;
            } else {
                const typeinfo = self.read64(vptr - 8);
                typeinfo_mapped = typeinfo != 0 and self.guestMemoryConst(typeinfo, 16) != null;
            }
        }
        const classification = semantic_fault_classifier.classify(.{
            .instruction = failure.instruction,
            .symbol = symbol_name,
            .address = failure.address,
            .rdi = self.regs.rdi,
            .rsi = self.regs.rsi,
            .rdx = self.regs.rdx,
            .rsp = self.regs.rsp,
            .rbp = self.regs.rbp,
            .rdi_mapped = self.guestMemoryConst(self.regs.rdi, 1) != null,
            .rsi_mapped = self.guestMemoryConst(self.regs.rsi, 1) != null,
            .rdx_mapped = self.guestMemoryConst(self.regs.rdx, 1) != null,
            .stack_mapped = self.guestMemoryConst(self.regs.rsp, 1) != null and
                (self.regs.rbp == 0 or self.guestMemoryConst(self.regs.rbp, 1) != null),
            .pointer_opaque = if (fault_policy) |policy| policy.kind == .opaque_identity and !policy.may_dereference else false,
            .pointer_owner = if (fault_policy) |policy| policy.owner else "",
            .vtable_header_mapped = vtable_header_mapped,
            .typeinfo_mapped = typeinfo_mapped,
            .live_allocation_vtable_history = self.hasLiveAllocationVtableHistory(self.regs.rdi),
            .instruction_in_generated_code = instruction_in_generated_code,
        });
        report.semantic_fault = .{
            .class = @tagName(classification.class),
            .reason = classification.reason,
            .next_subsystem = classification.next_subsystem,
            .current_symbol = symbol_name,
            .instruction = failure.instruction,
            .effective_address = failure.address,
        };
        var provenance = self.memory_regions.find(failure.address, @as(u64, failure.bytes));
        const pointer_attribution = switch (classification.class) {
            .bad_this_pointer,
            .bad_vtable_header,
            .bad_streambuf_pointer,
            .bad_typeinfo_pointer,
            .cxx_invalid_vtt,
            .cxx_object_model_null_vtable,
            .cxx_shared_control_block_null_vtable,
            => true,
            else => false,
        };
        if (pointer_attribution and provenance == null) provenance = self.memory_regions.find(self.regs.rdi, 1);
        if (pointer_attribution and provenance == null) provenance = self.memory_regions.find(self.regs.rsi, 1);
        if (provenance) |region| {
            report.semantic_fault.?.region_kind = @tagName(region.kind);
            report.semantic_fault.?.region_owner = region.owner;
            report.semantic_fault.?.region_start = region.start;
            report.semantic_fault.?.region_end = region.end;
            report.semantic_fault.?.region_readable = region.permissions.read;
            report.semantic_fault.?.region_writable = region.permissions.write;
            report.semantic_fault.?.region_executable = region.permissions.execute;
            report.semantic_fault.?.region_synthetic = region.isSynthetic();
        }
        var diagnostic_policy = fault_policy;
        if (pointer_attribution and diagnostic_policy == null) diagnostic_policy = self.pointer_firewall.policyAt(self.regs.rdi);
        if (pointer_attribution and diagnostic_policy == null) diagnostic_policy = self.pointer_firewall.policyAt(self.regs.rsi);
        if (diagnostic_policy) |policy| {
            report.semantic_fault.?.pointer_kind = @tagName(policy.kind);
            report.semantic_fault.?.pointer_owner = policy.owner;
            report.semantic_fault.?.pointer_may_dereference = policy.may_dereference;
            report.semantic_fault.?.pointer_may_execute = policy.may_execute;
        }
        if (symbol_name.len != 0) self.import_resolver.markCrashNearby(symbol_name);
    } else if (self.terminal_control_transfer) |failure| {
        const terminal_symbol = self.metadata.nearestSymbol(failure.instruction_address);
        const symbol_name = if (terminal_symbol) |symbol| symbol.name else "";
        const target_policy = self.pointer_firewall.policyAt(failure.target_address);
        if (failure.fault_class.len != 0) {
            report.semantic_fault = .{
                .class = failure.fault_class,
                .reason = failure.fault_evidence,
                .next_subsystem = failure.next_subsystem,
                .current_symbol = symbol_name,
                .instruction = failure.kind,
                .effective_address = failure.target_address,
            };
            if (std.mem.eql(u8, failure.fault_owner, "translated guest program")) {
                report.attribution = .{
                    .owner = .guest_application,
                    .authority = .diagnostic_only,
                    .evidence = failure.fault_evidence,
                    .next_action = failure.next_subsystem,
                };
            } else if (std.mem.eql(u8, failure.fault_owner, "Rosette runtime") or
                std.mem.eql(u8, failure.fault_owner, "Rosette dyld/import bridge"))
            {
                report.attribution = .{
                    .owner = .rosette_runtime,
                    .authority = .diagnostic_only,
                    .evidence = failure.fault_evidence,
                    .next_action = failure.next_subsystem,
                };
            }
        } else {
            const classification = semantic_fault_classifier.classify(.{
                .instruction = failure.kind,
                .symbol = symbol_name,
                .address = failure.target_address,
                .rdi = self.regs.rdi,
                .rsi = self.regs.rsi,
                .rdx = self.regs.rdx,
                .rsp = self.regs.rsp,
                .rbp = self.regs.rbp,
                .rdi_mapped = self.guestMemoryConst(self.regs.rdi, 1) != null,
                .rsi_mapped = self.guestMemoryConst(self.regs.rsi, 1) != null,
                .rdx_mapped = self.guestMemoryConst(self.regs.rdx, 1) != null,
                .stack_mapped = self.guestMemoryConst(self.regs.rsp, 1) != null,
                .pointer_opaque = if (target_policy) |policy| policy.kind == .opaque_identity and !policy.may_execute else false,
                .pointer_owner = if (target_policy) |policy| policy.owner else "",
                .live_allocation_vtable_history = self.hasLiveAllocationVtableHistory(self.regs.rdi),
            });
            report.semantic_fault = .{
                .class = @tagName(classification.class),
                .reason = classification.reason,
                .next_subsystem = classification.next_subsystem,
                .current_symbol = symbol_name,
                .instruction = failure.kind,
                .effective_address = failure.target_address,
            };
        }
        var transfer_region = self.memory_regions.find(failure.target_address, 1);
        if (transfer_region == null and failure.operand_address != 0) {
            transfer_region = self.memory_regions.find(failure.operand_address, @sizeOf(u64));
        }
        if (transfer_region == null and failure.object_vptr != 0) {
            transfer_region = self.memory_regions.find(failure.object_vptr, 1);
        }
        if (transfer_region) |region| {
            report.semantic_fault.?.region_kind = @tagName(region.kind);
            report.semantic_fault.?.region_owner = region.owner;
            report.semantic_fault.?.region_start = region.start;
            report.semantic_fault.?.region_end = region.end;
            report.semantic_fault.?.region_readable = region.permissions.read;
            report.semantic_fault.?.region_writable = region.permissions.write;
            report.semantic_fault.?.region_executable = region.permissions.execute;
            report.semantic_fault.?.region_synthetic = region.isSynthetic();
        }
        if (target_policy) |policy| {
            report.semantic_fault.?.pointer_kind = @tagName(policy.kind);
            report.semantic_fault.?.pointer_owner = policy.owner;
            report.semantic_fault.?.pointer_may_dereference = policy.may_dereference;
            report.semantic_fault.?.pointer_may_execute = policy.may_execute;
        }
    } else if (self.faulted) {
        report.semantic_fault = .{
            .class = @tagName(reason),
            .reason = attribution.evidence,
            .next_subsystem = attribution.next_action,
            .current_symbol = if (report.terminal_symbol) |symbol| symbol.symbol else "",
            .instruction = if (report.terminal_instruction) |instruction| instruction.op else "",
            .effective_address = self.regs.rip,
        };
    }

    const terminal_trace_count: usize = self.execution_history.countFor(self.active_guest_thread);
    if (terminal_trace_count > 0) {
        const latest = self.execution_history.latestFor(self.active_guest_thread) orelse TraceEntry{};
        var terminal = exit_diagnostics.TerminalInstruction{
            .address = latest.rip,
            .op = @tagName(latest.op),
            .length = latest.len,
        };
        if (self.guestMemoryConst(latest.rip, terminal.bytes.len)) |bytes| {
            terminal.byte_count = @intCast(@min(bytes.len, terminal.bytes.len));
            @memcpy(terminal.bytes[0..terminal.byte_count], bytes[0..terminal.byte_count]);
        }
        report.terminal_instruction = terminal;
        if (report.semantic_fault) |*semantic| {
            if (semantic.instruction.len == 0) semantic.instruction = terminal.op;
        }
    } else if (self.terminal_memory_failure) |failure| {
        if (failure.instruction_byte_count != 0) {
            report.terminal_instruction = .{
                .address = failure.instruction_address,
                .op = if (failure.decoded_instruction.len != 0) failure.decoded_instruction else failure.instruction,
                .length = failure.instruction_length,
                .bytes = failure.instruction_bytes,
                .byte_count = failure.instruction_byte_count,
            };
        }
    }

    var stack_buf: [16]exit_diagnostics.StackEntry = undefined;
    var stack_count: usize = 0;
    var stack_address = self.regs.rsp;
    while (stack_count < stack_buf.len) : (stack_address +%= 8) {
        const offset = self.addrToOffset(stack_address) orelse break;
        if (offset + 8 > self.mem.len) break;
        const value = self.read64(stack_address);
        stack_buf[stack_count] = .{ .slot_address = stack_address, .value = value };
        if (self.metadata.nearestSymbol(value)) |symbol| {
            stack_buf[stack_count].symbol = symbol.name;
            stack_buf[stack_count].symbol_offset = symbol.offset;
        }
        stack_count += 1;
    }
    report.stack_entries = stack_buf[0..stack_count];

    if (self.cxx_exceptions.last_throw) |thrown| {
        var exception_report = exit_diagnostics.CxxExceptionReport{
            .object_address = thrown.object_address,
            .type_info_address = thrown.type_info_address,
            .type_name = self.cxxExceptionTypeName(thrown.type_info_address) orelse "",
            .type_symbol = self.diagnosticSymbol(thrown.type_info_address),
            .destructor_address = thrown.destructor_address,
            .destructor_symbol = self.diagnosticSymbol(thrown.destructor_address),
            .throw_site = self.diagnosticSymbol(thrown.caller_address),
            .message = self.cxxExceptionMessage(thrown.object_address) orelse "",
            .catch_completed = self.cxx_exceptions.last_throw_caught,
            .active_catches = self.cxx_exceptions.active_catch_count,
            .classification = if (self.spirv_cross.last_classification != .unrelated)
                self.spirv_cross.lastLabel()
            else
                "general_cxx_exception",
        };
        if (thrown.allocation) |allocation| {
            exception_report.allocation_matched = true;
            exception_report.allocation_size = allocation.object_size;
            exception_report.allocation_site = self.diagnosticSymbol(allocation.caller_address);
        }
        if (self.last_unwind_inspection) |inspection| {
            exception_report.unwinder_available = inspection.metadata_frames != 0;
            exception_report.unwind_frames = inspection.frame_count;
            exception_report.cleanup_frames = inspection.cleanup_frames;
            exception_report.frame_chain_valid = inspection.frame_chain_valid;
            if (inspection.handler) |handler| {
                exception_report.handler_found = true;
                exception_report.handler_address = handler.landing_pad;
            }
            exception_report.phase_two_supported = inspection.phase_two_supported;
            exception_report.phase_two_installed = inspection.phase_two_installed;
            exception_report.cleanups_exhausted_without_handler = self.unwinder.exhaustedWithoutHandler();
        }
        report.cxx_exception = exception_report;
        const is_expected_probe = std.mem.eql(u8, exception_report.classification, "expected_dummy_probe_unwinding") or
            std.mem.eql(u8, exception_report.classification, "expected_dummy_probe_caught");

        if (!exception_report.catch_completed and !is_expected_probe) {
            report.detail = if (exception_report.cleanups_exhausted_without_handler)
                "Rosette executed every verified Itanium cleanup landing pad, but the active LSDA route contains no matching catch handler."
            else if (exception_report.phase_two_supported)
                "Rosette installed a verified Itanium phase-two landing-pad context before the later diagnostic stop."
            else
                "Rosette completed Itanium phase-one frame and catch inspection; this frame was not safe for phase-two context installation.";
        }
    }

    const memory_trace_count: usize = if (self.memory_trace_filled) MEMORY_TRACE_BUFFER_LEN else self.memory_trace_index;
    var memory_trace_buf: [MEMORY_TRACE_BUFFER_LEN]exit_diagnostics.MemoryAccessEvent = undefined;
    for (0..memory_trace_count) |i| {
        const index = if (self.memory_trace_filled)
            (self.memory_trace_index + i) % MEMORY_TRACE_BUFFER_LEN
        else
            i;
        memory_trace_buf[i] = self.memory_trace_entries[index];
    }
    report.recent_memory_accesses = memory_trace_buf[0..memory_trace_count];

    const import_trace_count: usize = if (self.import_trace_filled) IMPORT_TRACE_BUFFER_LEN else self.import_trace_index;
    if (import_trace_count > 0) {
        var import_trace_buf: [IMPORT_TRACE_BUFFER_LEN]exit_diagnostics.DependencyCall = undefined;
        for (0..import_trace_count) |i| {
            const idx = if (self.import_trace_filled)
                (self.import_trace_index + i) % IMPORT_TRACE_BUFFER_LEN
            else
                i;
            const entry = self.import_trace_entries[idx];
            import_trace_buf[i] = .{
                .symbol = entry.symbol,
                .image = entry.dylib,
                .stub_address = entry.stub_address,
                .return_address = entry.return_address,
                .synthetic_result = entry.synthetic_result,
                .caller_symbol = entry.caller_symbol,
                .caller_offset = entry.caller_offset,
            };
        }
        report.dependency_calls = import_trace_buf[0..import_trace_count];
        report.detail = "The interpreter did not execute these dynamic-library functions; the guest exit code is not authoritative.";
    }

    // The destination bounds the copy, not a separately-declared count. This
    // buffer was sized from TRACE_BUFFER_LEN (256) while the loop count came
    // from countFor() (512 after the history was partitioned per thread), so
    // the dump wrote 256 entries past the end of a stack array and killed the
    // process with SIGSEGV *while producing crash diagnostics* — the report
    // truncated mid-trace and every later diagnostic was lost. Two constants
    // that had to agree, with nothing enforcing it.
    if (terminal_trace_count > 0) {
        var raw_buf: [constants.TRACE_PER_THREAD_LEN]TraceEntry = undefined;
        const copied = self.execution_history.copyRecentInto(self.active_guest_thread, &raw_buf);
        var trace_buf: [constants.TRACE_PER_THREAD_LEN]exit_diagnostics.TraceEntry = undefined;
        for (raw_buf[0..copied], 0..) |entry, i| {
            trace_buf[i] = .{
                .thread_handle = entry.thread_handle,
                .rip = entry.rip,
                .op = @tagName(entry.op),
                .len = entry.len,
                .rsp = entry.rsp,
                .rax = entry.rax,
                .rbx = entry.rbx,
                .rcx = entry.rcx,
                .rdx = entry.rdx,
                .rsi = entry.rsi,
                .rdi = entry.rdi,
                .rbp = entry.rbp,
                .r8 = entry.r8,
                .r9 = entry.r9,
                .r10 = entry.r10,
                .r11 = entry.r11,
                .r12 = entry.r12,
                .r13 = entry.r13,
                .r14 = entry.r14,
                .r15 = entry.r15,
            };
        }
        report.last_instructions = trace_buf[0..copied];
    }

    exit_diagnostics.logExitReport(report);
}

pub fn releaseBarrier() void {
    if (comptime @import("builtin").target.cpu.arch == .aarch64) {
        asm volatile ("dmb ish" ::: .{ .memory = true });
    } else {
        asm volatile ("mfence" ::: .{ .memory = true });
    }
}

pub fn logAtomicDiagnostic(self: anytype, matched: bool, size: Size, addr: u64, expected: u64, actual: u64, replacement: u64, is_locked: bool, rax_before: u64, rflags_before: u32) void {
    const op_num = self.atomic_cmpxchg.operations;
    if (op_num <= 16 or (!matched and self.atomic_cmpxchg.mismatches <= 16)) {
        const subtract_expected_vs_actual = (expected -% actual) & maskForSize(size);
        const cf: u8 = @intFromBool((expected & maskForSize(size)) < (actual & maskForSize(size)));
        const of: u8 = @intFromBool(((expected ^ actual) & (expected ^ subtract_expected_vs_actual) & signBitForSize(size)) != 0);
        primitiveCapturePrint(
            "macho-processor: CMPXCHG#{d}: rip=0x{x} size={s} lock={} matched={} addr=0x{x} " ++
                "expected(ACC)=0x{x} actual(DEST)=0x{x} replacement(SRC)=0x{x} " ++
                "RAX_before=0x{x:0>16} subtract(AL-DEST)=0x{x} " ++
                "rflags_before=0x{x:0>8} rflags_after=0x{x:0>8} " ++
                "CF_expected={d} OF_expected={d} ZF={d} step={d} thread=0x{x} owner={s}\n",
            .{
                op_num,
                self.regs.rip,
                @tagName(size),
                is_locked,
                matched,
                addr,
                expected,
                actual,
                replacement,
                rax_before,
                subtract_expected_vs_actual,
                rflags_before,
                self.regs.rflags,
                cf,
                of,
                @as(u8, @intFromBool(matched)),
                self.executed_steps,
                self.active_guest_thread,
                self.metadata.symbolLabel(self.regs.rip),
            },
        );
    }
}
