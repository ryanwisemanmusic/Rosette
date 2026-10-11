// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const acceptance_gates = __ProcessInternals._acceptance_gates;
const builtin = __ProcessInternals._builtin;
const constants = __ProcessInternals._constants;
const contract = __ProcessInternals._contract;
const diagnostics_execution_profile = __ProcessInternals._diagnostics_execution_profile;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const fault_pause_transaction = __ProcessInternals._fault_pause_transaction;
const gpu = __ProcessInternals._gpu;
const guest_log = __ProcessInternals._guest_log;
const guest_log_channels = __ProcessInternals._guest_log_channels;
const guest_status_ledger = __ProcessInternals._guest_status_ledger;
const guest_wait_liveness = __ProcessInternals._guest_wait_liveness;
const interrupt_callback_transaction = __ProcessInternals._interrupt_callback_transaction;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const main = __ProcessInternals._main;
const monotone_witness = __ProcessInternals._monotone_witness;
const register_map = __ProcessInternals._register_map;
const run_budget = __ProcessInternals._run_budget;
const run_horizon = __ProcessInternals._run_horizon;
const run_journal = __ProcessInternals._run_journal;
const scheduler = __ProcessInternals._scheduler;
const std = __ProcessInternals._std;
const sync_object_registry = __ProcessInternals._sync_object_registry;
const translation_domain = __ProcessInternals._translation_domain;
const translation_economics = __ProcessInternals._translation_economics;
const unknown_inventory_mod = __ProcessInternals._unknown_inventory_mod;
const wait_audit = __ProcessInternals._wait_audit;
const wait_graph = __ProcessInternals._wait_graph;
const xenia_gpu_causal_trace = __ProcessInternals._xenia_gpu_causal_trace;
const xenia_memory_views = __ProcessInternals._xenia_memory_views;
const BankOccupancy = __ProcessInternals._BankOccupancy;
const effect_settle_steps = __ProcessInternals._effect_settle_steps;
const guestMemory = __ProcessInternals._guestMemory;
const guestMemoryConst = __ProcessInternals._guestMemoryConst;
const ms = __ProcessInternals._ms;
const decodeCacheSetBasesFor = MachOState.decodeCacheSetBasesFor;
const elapsedHostSeconds = MachOState.elapsedHostSeconds;
const logPipelineEvidence = MachOState.logPipelineEvidence;
const refreshVdSwapContract = MachOState.refreshVdSwapContract;
const refreshWaitGraphProgress = MachOState.refreshWaitGraphProgress;
const run = MachOState.run;
const runBudgetGuestWindowSummary = MachOState.runBudgetGuestWindowSummary;
const runBudgetGuestWindowVerdict = MachOState.runBudgetGuestWindowVerdict;
const sampleBankOccupancy = MachOState.sampleBankOccupancy;
const step = MachOState.step;
const translationDomainFor = MachOState.translationDomainFor;

pub fn logAuditContracts(self: anytype) void {
    self.logPipelineEvidence();
    const at_step = self.executed_steps;
    const board = &self.audit_gates;
    const gates = board.summary();
    const fingerprint = board.fingerprint();
    const changed = fingerprint != self.audit_gates_last_fingerprint;
    self.audit_gates_last_fingerprint = fingerprint;

    machoCapturePrint(
        "macho-processor: ACCEPTANCE GATES: depth={d}/{d} passed={d} failed={d} unevaluable={d} not_reached={d} observer_holes={d} unattributed={d} frontier={s} outcome={s} reason={s} owner={s} step={d}; a gate whose predecessor has not passed is not-reached rather than failed, so the frontier is the first thing genuinely missing and not the loudest zero downstream of it\n",
        .{
            gates.depth(),
            acceptance_gates.gate_count,
            gates.passed,
            gates.failed,
            gates.unevaluable,
            gates.not_reached,
            gates.observer_holes,
            gates.unattributed,
            if (gates.frontier) |gate| gate.label() else "<complete>",
            gates.frontier_outcome.label(),
            gates.frontier_reason.label(),
            gates.frontierOwner(),
            at_step,
        },
    );
    if (gates.frontier) |gate| {
        machoCapturePrint("  ACCEPTANCE GATE SUBJECT: {s}\n", .{gate.describe()});
        machoCapturePrint("  ACCEPTANCE GATE OUTCOME: {s}\n", .{gates.frontier_outcome.describe()});
        // The reason, by name, next to the outcome. Without it the row
        // said `FAILED detail=8` and the eight things it counted were
        // recoverable only by reading the code that produced them.
        machoCapturePrint("  ACCEPTANCE GATE REASON: {s} — {s}\n", .{
            gates.frontier_reason.label(),
            gates.frontier_reason.describe(),
        });
        if (gates.frontier_reason.observerHole()) {
            machoCapturePrint(
                "  ACCEPTANCE GATE REASON: this frontier is a hole in what Rosette looked at, not a fact about the emulator or the title. Wiring the observation is the work; the gate's nominal owner has nothing to answer for yet\n",
                .{},
            );
        }
        // The target gate's evidence has exactly one producer, and a
        // reader who arrives at `target-output-unjudgeable` otherwise has
        // to re-derive that every time. A draw is classified from the
        // render-target registers; those come only from the stateful
        // command processor; a batch it refused is a batch whose draws are
        // all classified as programming nothing.
        if (gates.frontier_reason == .target_output_unjudgeable) {
            const target = self.audit_render_target.summary();
            machoCapturePrint(
                "  ACCEPTANCE GATE EVIDENCE: the render-target classification rests on the stateful command processor and nothing else. executions={d} refusals={d} partial_tails={d} indirect_buffers={d} candidates={d} output_bearing={d}; a refused or partially-read batch classifies its draws as programming nothing, which is the same reading as a title that programmed nothing. Settle the executor's own numbers before reading the draw classification\n",
                .{
                    self.gpu_xenos_retained_executions,
                    self.gpu_xenos_retained_refusals,
                    self.gpu_xenos_runtime.retained_truncated_tails,
                    self.gpu_xenos_runtime.indirect_buffers,
                    target.candidates,
                    target.outputBearing(),
                },
            );
        }
    }
    // One greppable line carrying the whole board, at every checkpoint.
    // The nine detailed rows below only print when the board moves, which
    // over a long run meant a reader at an arbitrary step could see the
    // frontier and nothing else — and "what is not reached" is exactly the
    // question the board exists to answer.
    {
        var compact: [512]u8 = undefined;
        var used: usize = 0;
        inline for (@typeInfo(acceptance_gates.Gate).@"enum".fields) |field| {
            const gate: acceptance_gates.Gate = @enumFromInt(field.value);
            const record = board.record(gate);
            const written = std.fmt.bufPrint(compact[used..], "G{d}={s}({s}) ", .{
                field.value,
                record.outcome.label(),
                record.reason.label(),
            }) catch compact[used..used];
            used += written.len;
        }
        machoCapturePrint("  ACCEPTANCE BOARD: {s}fingerprint=0x{x:0>16}\n", .{ compact[0..used], fingerprint });
    }
    if (changed) {
        inline for (@typeInfo(acceptance_gates.Gate).@"enum".fields) |field| {
            const gate: acceptance_gates.Gate = @enumFromInt(field.value);
            const record = board.record(gate);
            machoCapturePrint(
                "  gate {s: <38} {s: <13} owner={s: <18} reason={s: <36} blocked_by={s: <38} detail={d} step={d}\n",
                .{
                    gate.label(),
                    record.outcome.label(),
                    record.reason.owner() orelse gate.owner(),
                    record.reason.label(),
                    if (board.blockedBy(gate)) |before| before.label() else "-",
                    record.detail,
                    record.step,
                },
            );
        }
    }

    // The host's protection granularity, as it kept costing during the
    // run rather than as it was proven once at startup. A startup proof
    // that the overlay enforces the console's page says nothing about a
    // mid-run protection change that widened with no exact record behind
    // it, and that is the shape the failure would take.
    const granularity = self.sparse_memory.granularity;
    machoCapturePrint(
        "macho-processor: PAGE GRANULARITY: effective={d}bytes host={d}bytes subhost_requests={d} shared_host_page={d} exact_records={d} unrecorded_widenings={d} step={d}; {s}\n",
        .{
            granularity.effectiveGranularity(),
            std.heap.page_size_min,
            granularity.subhost_requests,
            granularity.shared_host_page_requests,
            granularity.exact_records,
            granularity.unrecorded_widenings,
            at_step,
            granularity.describe(),
        },
    );

    // The manifest. Two runs that cannot be compared cannot be used to
    // decide whether a change helped.
    machoCapturePrint(
        "macho-processor: RUN MANIFEST: sealed={s} profile={s} run=0x{x:0>16} image=0x{x:0>16} features={d} ceiling={s}; {s}\n",
        .{
            if (self.audit_manifest.sealed) "YES" else "NO",
            self.audit_manifest.profile.label(),
            self.audit_manifest.identity.run_id,
            self.audit_manifest.identity.image_hash,
            self.audit_manifest.features.count(),
            self.audit_manifest.profile.ceilingSourceClass().label(),
            self.audit_manifest.profile.describe(),
        },
    );

    const journal = self.audit_journal.summary();
    machoCapturePrint(
        "macho-processor: RUN JOURNAL: completeness={s} events={d} materialized={d} compacted={d} groups={d}/{d} reserved={d}/{d} general={d}/{d} reserved_dropped={d} general_dropped={d} gaps={d}; identical wait/signal repetitions retain exact count and first/last-step envelopes without consuming another critical slot; {s}\n",
        .{
            journal.completeness.label(),
            journal.observed,
            journal.written,
            journal.compacted,
            journal.compaction_groups,
            run_journal.compaction_capacity,
            journal.reserved_used,
            run_journal.reserved_capacity,
            journal.general_used,
            run_journal.general_capacity,
            journal.reserved_dropped,
            journal.general_dropped,
            journal.observed_gaps,
            journal.completeness.describe(),
        },
    );

    const pause = self.audit_pause.standing();
    machoCapturePrint(
        "macho-processor: FAULT PAUSE TRANSACTION: standing={s} transactions={d} reports={d} unmatched={d} protocol_defects={d} pending_external_id=0x{x} termination={s} guest_causality={s}; {s}\n",
        .{
            pause.label(),
            self.audit_pause.count,
            self.audit_pause.pause_reports,
            self.audit_pause.unmatched_reports,
            self.audit_pause.protocol_defects,
            self.audit_pause.pending_external_id,
            self.audit_pause.termination.label(),
            if (pause.guestCausalityIntact()) "INTACT" else "SUSPENDED",
            pause.describe(),
        },
    );
    if (self.audit_pause.unmatched_reports != 0) {
        // The claim, and what answered it. An unmatched report suspends
        // every wait reading in the run, so the evidence that lifts the
        // suspension has to be as visible as the suspension was.
        if (self.audit_pause.refuted_by) |axis| {
            machoCapturePrint(
                "  FAULT PAUSE REFUTED: axis={s} margin={d} report_step={d} refuted_step={d} owner={s}; {s}\n",
                .{
                    axis.label(),
                    self.audit_pause.refutation_margin,
                    self.audit_pause.unmatched_report_step,
                    self.audit_pause.refuted_step,
                    pause.owner(),
                    axis.whyPausedGuestCannotAdvanceIt(),
                },
            );
        } else {
            machoCapturePrint(
                "  FAULT PAUSE UNANSWERED: report_step={d} owner={s}; no progress axis has risen above where it stood when the pause was reported, so the claim is neither matched to a transaction nor disproved. Every wait after this step is filed as a consequence until one of the two happens\n",
                .{ self.audit_pause.unmatched_report_step, pause.owner() },
            );
        }
        inline for (@typeInfo(fault_pause_transaction.ProgressAxis).@"enum".fields) |field| {
            const axis: fault_pause_transaction.ProgressAxis = @enumFromInt(field.value);
            machoCapturePrint(
                "  fault-pause axis {s: <24} at_report={d} latest={d} moved={d}\n",
                .{
                    axis.label(),
                    self.audit_pause.axis_at_report[field.value],
                    self.audit_pause.axis_latest[field.value],
                    self.audit_pause.axis_latest[field.value] -| self.audit_pause.axis_at_report[field.value],
                },
            );
        }
    }
    if (self.audit_pause.protocol_defects != 0 or
        self.audit_pause.pending_external_id != 0)
    {
        machoCapturePrint(
            "  FAULT PAUSE PROTOCOL: last={s} step={d} expected_external_id=0x{x} observed_external_id=0x{x} pending_step={d}; every non-zero producer transaction must attach to one guest-fault frontier and every guest-fault pause/resume bracket must carry the same id\n",
            .{
                self.audit_pause.last_protocol_defect.label(),
                self.audit_pause.last_protocol_defect_step,
                self.audit_pause.last_protocol_expected_id,
                self.audit_pause.last_protocol_observed_id,
                self.audit_pause.pending_external_id_step,
            },
        );
    }
    for (self.audit_pause.retained()) |transaction| {
        if (transaction.external_id == 0 and transaction.cause != .guest_fault) continue;
        machoCapturePrint(
            "  fault-pause transaction local_id={d} external_id={d} cause={s} stages(fault/pause/resume)={s}/{s}/{s} steps={d}/{d}/{d}\n",
            .{
                transaction.id,
                transaction.external_id,
                transaction.cause.label(),
                if (transaction.has(.fault_recorded)) "YES" else "NO",
                if (transaction.has(.pause_completed)) "YES" else "NO",
                if (transaction.has(.resume_completed)) "YES" else "NO",
                transaction.step[@intFromEnum(fault_pause_transaction.Stage.fault_recorded)],
                transaction.step[@intFromEnum(fault_pause_transaction.Stage.pause_completed)],
                transaction.step[@intFromEnum(fault_pause_transaction.Stage.resume_completed)],
            },
        );
    }

    const producer = self.audit_producer.verdict(
        at_step,
        self.wait_audit.witness.advancedSince(self.never_notified_witness),
        false,
    );
    machoCapturePrint(
        "macho-processor: PRODUCER LIVENESS: verdict={s} epoch={s} owner={s} epochs_after_ring={d} quiet_for={d} wait_object=0x{x} refusals={d} step={d}; {s}\n",
        .{
            producer.label(),
            self.audit_producer.current.label(),
            self.audit_producer.current.owner(),
            self.audit_producer.effectiveEpochsAfterRing(),
            self.audit_producer.quietSteps(at_step),
            self.audit_producer.currentWaitObject(),
            self.audit_producer.refusals,
            at_step,
            producer.describe(),
        },
    );
    machoCapturePrint(
        "  PRODUCER EPOCH MEANING: {s}\n",
        .{self.audit_producer.current.stalledMeans()},
    );

    const transport = self.audit_ring_transport.summary();
    const transport_verdict = self.audit_ring_transport.verdict();
    machoCapturePrint(
        "macho-processor: RING TRANSPORT: verdict={s} transitions={d} effective={d} guest={d} host={d} publication_gate={s} frontier={s}; {s}\n",
        .{
            transport_verdict.label(),
            transport.transitions,
            transport.effective,
            transport.guest_authentic,
            transport.host_sourced,
            if (self.audit_ring_transport.meetsPublicationGate()) "MET" else "unmet",
            if (self.audit_ring_transport.frontier()) |stage| stage.label() else "<complete>",
            transport_verdict.describe(),
        },
    );
    if (self.audit_ring_transport.printedButNotApplied()) |stage| {
        machoCapturePrint("  RING TRANSPORT GAP: {s}\n", .{stage.gapMeans()});
    }

    const pm4_authority_verdict = self.audit_pm4.verdict();
    const pm4_comparison = self.audit_pm4.comparison();
    machoCapturePrint(
        "macho-processor: PM4 AUTHORITY: verdict={s} batch=0x{x} accounts={d} dropped={d} comparable={s} disagreements={d} first_field={s} defect_class={s} left={d} right={d}; {s}\n",
        .{
            pm4_authority_verdict.label(),
            self.audit_pm4.batch_id,
            self.audit_pm4.count,
            self.audit_pm4.dropped,
            if (pm4_comparison.comparable) "YES" else "NO",
            pm4_comparison.disagreements,
            if (pm4_comparison.first_field) |field| field.label() else "-",
            // A defect total names nobody. Which class disagreed is the
            // difference between a truncated ring and an unrecognised
            // register, and those go to different people.
            if (pm4_comparison.first_defect_kind) |kind| kind.label() else "-",
            pm4_comparison.first_left,
            pm4_comparison.first_right,
            pm4_authority_verdict.describe(),
        },
    );
    // Per-class defect rows for every account, so a disagreement is read
    // from the classes rather than inferred from two totals.
    if (pm4_comparison.comparable and !pm4_comparison.agrees()) {
        inline for (@typeInfo(gpu.pm4_authority.DefectKind).@"enum".fields) |field| {
            const kind: gpu.pm4_authority.DefectKind = @enumFromInt(field.value);
            var differs = false;
            var previous: ?u64 = null;
            for (self.audit_pm4.retained()) |account| {
                const value = account.defects[field.value];
                if (previous) |seen| {
                    if (seen != value) differs = true;
                }
                previous = value;
            }
            if (differs) {
                machoCapturePrint("  PM4 DEFECT CLASS {s: <22} semantic={s}", .{
                    kind.label(),
                    if (kind.continuationChangesSemantics()) "YES" else "NO",
                });
                for (self.audit_pm4.retained()) |account| {
                    machoCapturePrint(" {s}={d}", .{ account.decoder.label(), account.defects[field.value] });
                }
                machoCapturePrint("\n", .{});
            }
        }
    }
    for (self.audit_pm4.retained(), 0..) |account, account_index| {
        machoCapturePrint(
            "  PM4 ACCOUNT #{d}: decoder={s} domain={s} source={s} batch=0x{x} dwords={d} packets(root/nested/total)={d}/{d}/{d} indirect_refs={d} register_intents={d} draws={d} event_writes={d} swaps={d} defects={d}\n",
            .{
                account_index + 1,
                account.decoder.label(),
                account.domain.label(),
                account.source.label(),
                account.batch_id,
                account.dwords_examined,
                account.root_packets,
                account.nested_packets,
                account.packets(),
                account.indirect_references,
                account.register_writes,
                account.draws,
                account.event_writes,
                account.swaps,
                account.totalDefects(),
            },
        );
    }

    const target = self.audit_render_target.summary();
    machoCapturePrint(
        "macho-processor: RENDER TARGET EVIDENCE: candidates={d} target_backed={d} memory_export={d} resolve_only={d} no_output={d} dropped_by_emulator={d} unclassified={d} output_bearing={d} first_pixel={d} frontier={s}; {s}\n",
        .{
            target.candidates,
            target.target_backed,
            target.memory_export,
            target.resolve_only,
            target.intentional_no_output,
            target.emulator_dropped,
            target.unclassified,
            target.outputBearing(),
            target.first_pixel_candidates,
            if (self.audit_render_target.frontier()) |verdict| verdict.label() else "<complete>",
            if (self.audit_render_target.frontier()) |verdict| verdict.gapMeans() else "every verdict has been proven by at least one candidate",
        },
    );

    const registers = self.audit_registers.summary();
    const register_verdict = self.audit_registers.verdict();
    machoCapturePrint(
        "macho-processor: XENOS REGISTER STATE: verdict={s} owner={s} writes={d} distinct={d} target_writes={d} target_nonzero={d}/{d} aperture_silent_pm4_busy={s}; {s}\n",
        .{
            register_verdict.label(),
            register_verdict.owner(),
            registers.writes,
            registers.distinct,
            registers.target_writes,
            registers.target_nonzero,
            gpu.xenos_register_state.target_registers.len,
            if (registers.apertureSilentWhilePm4Busy()) "YES" else "NO",
            register_verdict.describe(),
        },
    );

    const edram_verdict = self.audit_edram.verdict();
    const resolve_verdict = self.audit_resolve.verdict();
    machoCapturePrint(
        "macho-processor: EDRAM AND RESOLVE: edram={s} ranges={d} writes={d} resolve={s} resolves={d} guest_visible_changes={d} frontier={s}; {s}\n",
        .{
            edram_verdict.label(),
            self.audit_edram.summary().ranges,
            self.audit_edram.summary().writes,
            resolve_verdict.label(),
            self.audit_resolve.summary().resolves,
            self.audit_resolve.summary().guest_visible_changes,
            if (self.audit_resolve.frontier()) |stage| stage.label() else "<complete>",
            edram_verdict.describe(),
        },
    );

    const interrupts = self.audit_interrupts.summary();
    const interrupt_verdict = self.audit_interrupts.verdict();
    const callback_transaction = &self.interrupt_callback_transaction;
    machoCapturePrint(
        "macho-processor: INTERRUPT EFFECT: verdict={s} deliveries={d} entered={d} returned={d} mutations={d} releases={d} wrong_object={d} outstanding={d} frontier={s}; {s}\n",
        .{
            interrupt_verdict.label(),
            interrupts.deliveries,
            interrupts.entered,
            interrupts.returned,
            interrupts.mutations,
            interrupts.releases,
            interrupts.wrong_object,
            interrupts.outstanding,
            if (self.audit_interrupts.frontier()) |link| link.label() else "<complete>",
            interrupt_verdict.describe(),
        },
    );
    // Which causes were ever raised, and whether the evidence permits the
    // conclusion the verdict invites.
    //
    // `ENTERED-WITHOUT-EFFECT` reads as a finding against the title's
    // handler, and it is only that if the handler was asked more than one
    // question. The run this was written against raised `source=0` on
    // every one of its deliveries: the handler was entered thirty-two
    // times and asked the same thing each time, and the report said the
    // handler was not doing what the waiter needed.
    if (interrupts.deliveries != 0) {
        machoCapturePrint(
            "  INTERRUPT CAUSES: raised={d}/{d} sole={s} attributed={d}/{d} unattributed={d} census={s} permits_handler_conclusion={s}; {s}\n",
            .{
                self.audit_interrupts.causesRaised(),
                gpu.interrupt_effect.cause_count,
                if (self.audit_interrupts.soleCause()) |cause| cause.label() else "-",
                // The histogram's own coverage. `deliveries` is reconciled
                // to the emulator's reported total and this table is not,
                // so the two are different observers and the gap between
                // them belongs on the line rather than in the reader's
                // head.
                interrupts.attributed(),
                interrupts.deliveries,
                interrupts.unattributed(),
                if (interrupts.causeCensusComplete()) "complete" else "PARTIAL",
                if (self.audit_interrupts.permitsHandlerConclusion()) "YES" else "NO",
                if (!interrupts.causeCensusComplete())
                    "the cause histogram below covers only the deliveries Rosette classified; the rest were reported by the emulator and never assigned a cause. That is a hole in this observer, not extra interrupts, and no cause-diversity conclusion may be drawn from a partial census"
                else if (self.audit_interrupts.permitsHandlerConclusion())
                    "a returned callback has a named expected object and a complete effect observation"
                else
                    "cause diversity alone proves no defect. Identify the expected guest object and observe its state through a real callback; do not synthesize interrupts to obtain coverage",
            },
        );
        // The raw source values the emulator raised, read from the
        // dispatch transaction rather than from the cause mapping, so a
        // source the console defines and this build does not is visible as
        // itself instead of as `unknown`.
        machoCapturePrint(
            "  INTERRUPT SOURCES: distinct={d} sole=0x{x} unbucketed={d} last=0x{x} last_cpu={d}\n",
            .{
                callback_transaction.sourceDiversity(),
                callback_transaction.soleSource() orelse 0,
                callback_transaction.unbucketed_sources,
                callback_transaction.last_source,
                callback_transaction.last_cpu,
            },
        );
        for (callback_transaction.sources[0..callback_transaction.distinct_sources]) |slot| {
            machoCapturePrint(
                "  interrupt-source 0x{x: <8} cause={s: <30} raised={d} first_step={d} last_step={d}\n",
                .{
                    slot.source,
                    gpu.interrupt_effect.causeOfSource(slot.source).label(),
                    slot.count,
                    slot.first_step,
                    slot.last_step,
                },
            );
        }
        inline for (@typeInfo(gpu.interrupt_effect.Cause).@"enum".fields) |field| {
            const cause: gpu.interrupt_effect.Cause = @enumFromInt(field.value);
            const raised = self.audit_interrupts.by_cause[cause.bucket()];
            machoCapturePrint(
                "  interrupt-cause {s: <30} source_code=0x{x} raised={d} allowed={s}\n",
                .{
                    cause.label(),
                    cause.sourceCode(),
                    raised,
                    if (self.audit_interrupts.filter.allows(cause)) "YES" else "NO",
                },
            );
        }
        // The payload the handler actually read, for the deliveries that
        // did not reach a waiter. The verdict already says to look at the
        // cause code and the status value; these are them.
        var shown: usize = 0;
        for (self.audit_interrupts.retained()) |delivery| {
            if (delivery.has(.waiter_released)) continue;
            if (shown >= 8) break;
            shown += 1;
            machoCapturePrint(
                "  interrupt-delivery id={d} cause={s} source=0x{x} status=0x{x} callback=0x{x} user_data=0x{x} expected_object=0x{x} mutated_object=0x{x} waiter_object=0x{x} queued={d} entered={d} returned={d} first_gap={s}\n",
                .{
                    delivery.id,
                    delivery.cause.label(),
                    delivery.source_code,
                    delivery.status_value,
                    delivery.callback,
                    delivery.user_data,
                    delivery.expected_object,
                    delivery.mutated_object,
                    delivery.waiter_object,
                    delivery.queued_step,
                    delivery.entered_step,
                    delivery.returned_step,
                    if (delivery.firstGap()) |link| link.label() else "<complete>",
                },
            );
        }
    }

    const custody = self.audit_frames.verdict();
    machoCapturePrint(
        "macho-processor: FRAME CUSTODY CHAIN: verdict={s} offered={d} authentic={d} diagnostic={d} synthetic={d} unchanged={d} unreadable={d} copy_failed={d} frontier={s} stable={s}; {s}\n",
        .{
            custody.label(),
            self.audit_frames.offered,
            self.audit_frames.tally.authenticFrames(),
            self.audit_frames.tally.diagnostic_presented,
            self.audit_frames.tally.synthetic_presented,
            self.audit_frames.tally.guest_unchanged,
            self.audit_frames.tally.guest_unreadable,
            self.audit_frames.tally.guest_copy_failed,
            if (self.audit_frames.authenticFrontier()) |edge| edge.label() else "<complete>",
            if (self.audit_frames.stableOutput()) "YES" else "NO",
            custody.describe(),
        },
    );

    const sync = self.audit_sync.summary();
    machoCapturePrint(
        "macho-processor: SYNC OBJECT REGISTRY: objects={d} healthy={d} missing_notifier={d} quiet_by_role={d} orphan_signal={d} unclassified_silence={d} classified={d} attributed={d} classification_debt={d}; a never-notified idle worker and a never-notified GPU completion are identical in every counter and are opposite findings — the role is what separates them, and an unclassified object is neither promoted nor dismissed\n",
        .{
            sync.objects,
            sync.healthy,
            sync.missing_notifier,
            sync.quiet_by_role,
            sync.orphan_signal,
            sync.unclassified_silence,
            sync.classified,
            sync.fully_attributed,
            sync.classificationDebt(),
        },
    );
    if (self.audit_sync.firstSubject()) |subject| {
        machoCapturePrint(
            "  SYNC REGISTRY SUBJECT: object=0x{x} handle=0x{x} kind={s} role={s} waits={d} timeouts={d} signals={d} notifier_owner={s}; {s}\n",
            .{
                subject.identity.address.guest_virtual,
                subject.identity.handle,
                subject.identity.kindOf().label(),
                subject.identity.roleOf().label(),
                subject.activity.waits,
                subject.activity.timeouts,
                subject.activity.signals,
                subject.identity.roleOf().notifierOwner(),
                subject.standing().describe(),
            },
        );
    }
    // Keep the four objects that the latest Xenia run made actionable in
    // a fixed, grep-friendly table. The lifecycle counters are emulator
    // observations; they do not replace the wait graph's stricter proof
    // of a blocked waiter being released by a matching signal.
    for ([_]u32{ 0x827C_EC14, 0x827C_EC28, 0x827C_EC38, 0x4000_4BF4 }) |watched_target| {
        var found: ?sync_object_registry.Entry = null;
        for (self.audit_sync.retained()) |entry| {
            if (entry.identity.address.guest_virtual == watched_target) {
                found = entry;
                break;
            }
        }
        if (found) |entry| {
            const operation: sync_object_registry.LifecycleOperation =
                @enumFromInt(entry.lifecycle_last_operation);
            machoCapturePrint(
                "  SYNC LIFECYCLE TABLE: object=0x{x:0>8} observed=YES handle=0x{x:0>8} kind={s} creates={d} initializes={d} bindings={d} references={d} waits(begin/return/success)={d}/{d}/{d} signals={d} resets={d} last={s} last_thread=0x{x} last_step={d} last_pc=0x{x} last_lr=0x{x} state_after_valid={s} state_after=0x{x}\n",
                .{
                    watched_target,
                    entry.identity.handle,
                    entry.identity.kindOf().label(),
                    entry.lifecycle_creates,
                    entry.lifecycle_initializes,
                    entry.lifecycle_bindings,
                    entry.lifecycle_references,
                    entry.lifecycle_wait_begins,
                    entry.lifecycle_wait_returns,
                    entry.lifecycle_success_returns,
                    entry.lifecycle_signals,
                    entry.lifecycle_resets,
                    operation.label(),
                    entry.lifecycle_last_thread,
                    entry.lifecycle_last_step,
                    entry.lifecycle_last_location.guest_pc,
                    entry.lifecycle_last_location.guest_lr,
                    if (entry.lifecycle_last_state_after_valid) "YES" else "NO",
                    entry.lifecycle_last_state_after,
                },
            );
        } else {
            machoCapturePrint(
                "  SYNC LIFECYCLE TABLE: object=0x{x:0>8} observed=NO handle=0x00000000 kind=unknown creates=0 initializes=0 bindings=0 references=0 waits(begin/return/success)=0/0/0 signals=0 resets=0 last=unknown last_thread=0x0 last_step=0 last_pc=0x0 last_lr=0x0 state_after_valid=NO state_after=0x0\n",
                .{watched_target},
            );
        }
    }

    const admission = self.audit_admission.admission();
    machoCapturePrint(
        "macho-processor: FEATURE ADMISSION: admission={s} profile={s} encounters={d} required={d} unclassified={d} diagnostic_fallbacks={d} interventions(enabled/fired/fabricating)={d}/{d}/{d} effective_class={s}; {s}\n",
        .{
            admission.label(),
            self.audit_admission.profile.label(),
            self.audit_admission.summary().encounters,
            self.audit_admission.summary().required,
            self.audit_admission.summary().unclassified,
            self.audit_admission.summary().diagnostic_fallbacks,
            self.audit_admission.summary().interventions_enabled,
            self.audit_admission.summary().interventions_fired,
            self.audit_admission.summary().fabricating_enabled,
            self.audit_admission.effectiveSourceClass().label(),
            admission.describe(),
        },
    );

    const budget_totals = self.runBudgetGuestWindowSummary();
    const budget_verdict = self.runBudgetGuestWindowVerdict(budget_totals);
    const external_progress_fresh = self.ready.hasRecentExternalProgress(self.executed_steps);
    machoCapturePrint(
        "macho-processor: RUN BUDGET: verdict={s} guest_ms_per_host_s={d} required={d} observer_percent={d} dominant_phase={s} external_progress(fresh/step)={s}/{d}; {s}\n",
        .{
            budget_verdict.label(),
            budget_totals.guestMsPerHostSecond(),
            self.audit_budget.required_guest_ms_per_host_second,
            budget_totals.observerPercent(),
            if (budget_totals.dominantPhase()) |phase| phase.label() else "-",
            if (external_progress_fresh) "YES" else "NO",
            self.ready.externalProgressStep(),
            budget_verdict.describe(),
        },
    );
    // Where the sampled program counter has been landing. `RUN BUDGET`
    // names a phase and the phase is always `guest-execution`; this is the
    // level down, and it is the difference between "the run is slow" and
    // "the samples are inside the emulator's own PowerPC JIT, so the cost
    // is double translation rather than a defect".
    {
        const profile = &self.startup.profile;
        const totals = profile.summary();
        if (totals.samples != 0) {
            machoCapturePrint(
                "macho-processor: EXECUTION PROFILE: samples={d} distinct={d} unretained={d} readable={s} decisive={s} dominant={s} dominant_share={d}% unaccounted={d}%; {s}\n",
                .{
                    totals.samples,
                    totals.distinct,
                    totals.unretained,
                    if (totals.readable()) "YES" else "NO",
                    if (totals.dominantIsDecisive()) "YES" else "NO",
                    if (totals.dominantRegion()) |region| region.label() else "-",
                    if (totals.dominantRegion()) |region|
                        totals.percentOf(totals.by_region[@intFromEnum(region)])
                    else
                        0,
                    totals.unaccountedPercent(),
                    if (!totals.readable())
                        "too few samples for a share to mean anything yet. The rows below are what has been seen, not a measurement"
                    else if (!totals.dominantIsDecisive())
                        "the classifier could not place more of the samples than any region holds, so this profile has not identified anything yet. The unaccounted share is the number to reduce, and it is Rosette's"
                    else if (totals.dominantRegion()) |region|
                        region.describe()
                    else
                        "no region holds the samples",
                },
            );
            inline for (@typeInfo(diagnostics_execution_profile.Region).@"enum".fields) |field| {
                const region: diagnostics_execution_profile.Region = @enumFromInt(field.value);
                const count = totals.by_region[field.value];
                if (count != 0) machoCapturePrint(
                    "  execution-profile region {s: <24} samples={d} share={d}%\n",
                    .{ region.label(), count, totals.percentOf(count) },
                );
            }
            var hottest: [6]diagnostics_execution_profile.Entry = undefined;
            const written = profile.hottest(&hottest);
            for (hottest[0..written]) |entry| {
                if (entry.samples == 0) continue;
                machoCapturePrint(
                    "  execution-profile symbol samples={d} share={d}% region={s: <24} witness_rip=0x{x} first_step={d} last_step={d} {s}\n",
                    .{
                        entry.samples,
                        totals.percentOf(entry.samples),
                        entry.region.label(),
                        entry.witness_rip,
                        entry.first_step,
                        entry.last_step,
                        entry.name,
                    },
                );
            }
        }
    }

    // The pool composition, whether or not it decided the verdict. It is
    // the number that tells an indexing problem from a working set that
    // does not fit, and suppressing the verdict must not also suppress the
    // reading — the point is that a conflict-dominated pool the run barely
    // touches is a true statement that is not the run's finding.
    inline for (@typeInfo(run_budget.Pool).@"enum".fields) |field| {
        const which: run_budget.Pool = @enumFromInt(field.value);
        const stats = self.audit_budget.pools[field.value];
        // An `if` rather than a `continue`: this loop is unrolled at
        // compile time and the condition is not, so a `continue` here is
        // comptime control flow inside a runtime block.
        if (stats.fills != 0 or stats.hits != 0) machoCapturePrint(
            "  run-budget pool {s: <18} hits={d} fills={d} conflicts={d} stale={d} hit_rate={d}% miss={d}bp conflict_dominated={s} material={s}; {s}\n",
            .{
                which.label(),
                stats.hits,
                stats.fills,
                stats.conflict_evictions,
                stats.stale_refills,
                stats.hitRatePercent(),
                stats.missBasisPoints(),
                if (stats.conflictDominated()) "YES" else "NO",
                if (stats.missBasisPoints() >= run_budget.material_miss_basis_points) "YES" else "NO",
                if (stats.thrashing())
                    "the pool evicts live work and misses often enough for that to be where the host time goes"
                else if (stats.conflictDominated())
                    "the pool evicts live work and the run barely refills it, so this describes the shape of the misses and not where the run's time went. It is worth fixing and it is not the reason this run is slow"
                else
                    "the misses are not dominated by conflicts",
            },
        );
    }

    const imports = self.audit_imports.verdict();
    machoCapturePrint(
        "macho-processor: IMPORT INTEGRITY: verdict={s} imports={d} bound={d} unresolved={d} on_chain={d} unsafe_on_chain={d} abi_defects={d} permits_graphics_conclusion={s}; {s}\n",
        .{
            imports.label(),
            self.audit_imports.summary().imports,
            self.audit_imports.summary().bound,
            self.audit_imports.summary().unresolved,
            self.audit_imports.summary().on_chain,
            self.audit_imports.summary().unsafe_on_chain,
            self.audit_imports.summary().abi_defects,
            if (imports.permitsGraphicsConclusion()) "YES" else "NO",
            imports.describe(),
        },
    );

    // The controlled vectors and the video-contract table are the two
    // pieces of work the audit asks for next. Printed even when empty so
    // the absence is a visible piece of outstanding work rather than a
    // silent one.
    const vectors = self.audit_vectors.summary();
    machoCapturePrint(
        "macho-processor: CONTROLLED VECTORS: run={d}/{d} passed={d} fell_short={d} skipped={d} first_failure={s} target_gate={s}; a known clear, triangle and resolve through this same command processor separate `the emulator cannot render` from `this title has not asked it to`. None run is outstanding work, not a passing grade\n",
        .{
            vectors.run,
            gpu.controlled_vectors.vector_count,
            vectors.passed,
            vectors.fell_short,
            vectors.skipped,
            if (vectors.first_failure) |vector| vector.label() else "<none>",
            if (self.audit_vectors.meetsTargetGate()) "MET" else "unmet",
        },
    );
    const video = self.audit_video.summary();
    machoCapturePrint(
        "macho-processor: VIDEO CONTRACT: demanded={d} acceptable={d} actionable(value/side_effect/missing)={d}/{d}/{d} stubs_on_chain={d} probes_missing={d} next={s}; a stub the title ignores is not work and a stub whose side effect it waits on is the highest-value class here\n",
        .{
            video.demanded,
            video.acceptable,
            video.actionable_value,
            video.actionable_side_effect,
            video.missing,
            video.stubs_on_chain,
            video.probes_missing,
            if (self.audit_video.nextSubject()) |entry| entry.which.label() else "<none>",
        },
    );
}

pub fn logMonotoneWitnesses(self: anytype) void {
    const ledger = &self.monotone_witness;
    const totals = ledger.summary();
    if (totals.observed == 0) return;
    const fingerprint = ledger.fingerprint();
    const changed = fingerprint != self.monotone_witness_last_fingerprint;
    self.monotone_witness_last_fingerprint = fingerprint;

    machoCapturePrint(
        "macho-processor: MONOTONE WITNESS: subjects={d} required(closure/total/observed/corroborated/agreement-debt/unclaimed)={s}/{d}/{d}/{d}/{d}/{d} corroborated={d} uncorroborated={d} explained={d} unexplained={d} settled_unexplained={d} regressions={d} resolutions={d} statements={d} worst_quiet_steps={d} step={d}; a witness below the floor is undercounting, and the floor is the only number a report may quote. Where the short witness rides a throttled line its silence is about the carrier, and its last step is when that carrier stopped speaking rather than when the mechanism stopped\n",
        .{
            totals.observed,
            if (totals.required_observed == monotone_witness.required_subject_count) "YES" else "NO",
            monotone_witness.required_subject_count,
            totals.required_observed,
            totals.required_corroborated,
            totals.required_agreement_debt,
            totals.required_unclaimed,
            totals.corroborated,
            totals.uncorroborated,
            totals.explained,
            totals.unexplained,
            totals.settled_unexplained,
            totals.regressions,
            totals.resolutions,
            totals.statements,
            totals.worst_quiet_steps,
            self.executed_steps,
        },
    );
    if (!changed and totals.judgeableDefects() == 0) return;
    inline for (@typeInfo(monotone_witness.Subject).@"enum".fields) |field| {
        const subject: monotone_witness.Subject = @enumFromInt(field.value);
        const result = ledger.reconcile(subject);
        if (result.finding != .unobserved) {
            machoCapturePrint(
                "  witness {s: <22} {s: <34} floor={d: <8} by={s: <28} floor_step={d} short={s: <28} short_count={d} short_step={d} quiet={d} mechanism_owner={s} absence_quotable={s}\n",
                .{
                    result.finding.label(),
                    subject.label(),
                    result.floor,
                    if (result.floor_witness) |which| which.label() else "-",
                    result.floor_step,
                    if (result.short_witness) |which| which.label() else "-",
                    result.short_count,
                    result.short_step,
                    result.short_quiet_steps,
                    subject.mechanismOwner(),
                    if (result.finding.absenceIsQuotable()) "YES" else "NO",
                },
            );
        }
    }
    if (ledger.firstDefect()) |first| {
        machoCapturePrint(
            "  MONOTONE WITNESS SUBJECT: {s} settled={s}; {s}\n",
            .{
                first.subject.label(),
                if (ledger.settledDefect(first.subject)) "YES" else "NO",
                first.finding.guidance(),
            },
        );
        if (first.short_witness) |which| {
            if (!which.countsEveryOccurrence()) {
                machoCapturePrint(
                    "  MONOTONE WITNESS CARRIER: {s} — {s}\n",
                    .{ which.label(), which.undercountExcuse() },
                );
            }
        }
    }
}

pub fn logInterruptCallbackLedger(ledger: *const interrupt_callback_transaction.Ledger, prefix: []const u8) void {
    const finding = ledger.finding();
    const gap = ledger.firstGap();
    machoCapturePrint(
        "macho-processor: {s}: domain={s} finding={s} first_gap={s} owner={s} registered={d} attempts={d} returns={d} skips={d} deferrals={d} callback=0x{x:0>8} user_data=0x{x:0>8} last(id/source/cpu/duration_ms)={d}/{d}/{d}/{d} context(before/after/changed)={d}/{d}/{d} payload(samples/changed/appeared)={d}/{d}/{d} effect={s} counters_valid={s} first_step={d} first(registration/dispatch/return)={d}/{d}/{d} last_step={d}; {s}\n",
        .{
            prefix,
            ledger.domain.label(),
            finding.label(),
            if (gap) |stage| stage.label() else "<complete>",
            if (gap) |stage| stage.owner() else "-",
            ledger.registrations,
            ledger.dispatch_attempts,
            ledger.callback_returns,
            ledger.dispatch_skips,
            ledger.dispatch_deferrals,
            ledger.callback_address,
            ledger.user_data,
            ledger.last_dispatch_id,
            ledger.last_source,
            ledger.last_cpu,
            ledger.last_duration_ms,
            ledger.context_before_samples,
            ledger.context_after_samples,
            ledger.context_changes,
            ledger.payload_samples,
            ledger.payload_changes,
            ledger.payload_appearances,
            ledger.effect().label(),
            if (ledger.counterInvariantHolds()) "YES" else "NO",
            ledger.first_step,
            ledger.first_registration_step,
            ledger.first_dispatch_step,
            ledger.first_return_step,
            ledger.last_step,
            finding.guidance(),
        },
    );
    if (ledger.superseded) {
        machoCapturePrint(
            "  {s}: superseded by callback=0x{x:0>8} at step={d}; this registration stood down when the real owner arrived, so its dispatch count is the expected outcome and not a missing interrupt producer\n",
            .{ prefix, ledger.successor_callback, ledger.superseded_step },
        );
    }
    // The sources this domain has actually raised. A handler entered many
    // times with one source has been asked one question many times, and
    // nothing else in the report can say so.
    if (ledger.sourceDiversity() != 0) {
        machoCapturePrint(
            "  {s}: sources(distinct/unbucketed)={d}/{d} sole=0x{x}\n",
            .{
                prefix,
                ledger.sourceDiversity(),
                ledger.unbucketed_sources,
                ledger.soleSource() orelse 0,
            },
        );
    }
}

pub fn logInterruptCallbackTransaction(self: anytype) void {
    logInterruptCallbackLedger(&self.interrupt_callback_transaction, "XENIA INTERRUPT CALLBACK");
    if (self.host_interrupt_callback_transaction.observed_mask != 0) {
        logInterruptCallbackLedger(&self.host_interrupt_callback_transaction, "XENIA HOST INTERRUPT CALLBACK");
    }
}

pub fn logRegisterJournal(self: anytype) void {
    const journal = &self.gpu_xenos_runtime.executor.register_file.journal;
    const totals = journal.summary();

    machoCapturePrint(
        "macho-processor: XENOS REGISTER JOURNAL: verdict={s} writes={d} out_of_range={d} blocks_touched={d}/{d} target_writes={d} target_nonzero={d}/{d} step={d}; {s}\n",
        .{
            totals.verdict.label(),
            totals.writes,
            totals.unknown_writes,
            totals.blocks_touched,
            gpu.register_journal.block_count,
            totals.target_writes,
            totals.target_nonzero,
            gpu.register_journal.target_registers.len,
            self.executed_steps,
            totals.verdict.guidance(),
        },
    );
    machoCapturePrint("  REGISTER JOURNAL OWNER: {s}\n", .{totals.verdict.owner()});

    // The register aperture and this journal count different things, and a
    // reader who sees only the first concludes the title never touched its
    // GPU. The aperture counts MMIO stores into the register window; this
    // journal counts registers written by PM4 packets the command processor
    // executed. A title that programs its GPU through the ring — which is
    // the normal path — leaves the aperture at zero forever while writing
    // hundreds of registers. Printed together so the zero cannot be read as
    // an absence of register programming.
    const aperture_accesses = self.gpu_register_aperture.total_reads +
        self.gpu_register_aperture.total_writes;
    machoCapturePrint(
        "  REGISTER PATH SPLIT: mmio_aperture(reads+writes)={d} pm4_journal_writes={d}; {s}\n",
        .{
            aperture_accesses,
            totals.writes,
            if (aperture_accesses == 0 and totals.writes != 0)
                "the aperture is untouched and the PM4 path is busy, which is the normal shape for a title that programs its GPU through the command ring. An aperture verdict of never_accessed is not evidence that registers were not programmed"
            else if (aperture_accesses == 0 and totals.writes == 0)
                "neither path has carried a register write, so no register programming has been observed by any route"
            else if (aperture_accesses != 0 and totals.writes == 0)
                "the title stores directly into the register aperture and no PM4 packet has programmed a register; this is the reverse of the usual shape and worth confirming against the ring"
            else
                "both paths carry register writes; state may be programmed from either, so a register's final value is whichever path wrote last",
        },
    );

    inline for (@typeInfo(gpu.RegisterBlock).@"enum".fields) |field| {
        const which: gpu.RegisterBlock = @enumFromInt(field.value);
        const record = journal.block(which);
        machoCapturePrint(
            "  register block {s: <20} writes={d: <8} named={d: <8} groups={d: <5} first=0x{x:0>4} last=0x{x:0>4} last_value=0x{x:0>8}; {s}\n",
            .{
                which.label(),
                record.writes,
                record.named_writes,
                record.distinct_sampled,
                record.first_register,
                record.last_register,
                record.last_value,
                which.meaning(),
            },
        );
    }
    const in_range_writes = journal.writes -| journal.out_of_range_writes;
    const exact_table_writes = in_range_writes -| journal.range_classified_writes;
    machoCapturePrint(
        "  REGISTER BLOCK CONFIDENCE: exact={d}/{d} fallback={d} exact_unowned={d} unknown_in_range={d} table_ranges={d}; the Xenos index space is interleaved, so a block total carried by fallback is an approximation, exact_unowned is a real Xenia-table entry without a Rosette functional owner, and unknown_in_range is the only vocabulary gap\n",
        .{
            exact_table_writes,
            in_range_writes,
            journal.range_classified_writes,
            journal.exact_unowned_writes,
            journal.unknown_in_range_writes,
            register_map.xenia_register_table_ranges.len,
        },
    );
    for (gpu.register_journal.target_registers) |register| {
        const record = journal.target(register).?;
        machoCapturePrint(
            "  target register 0x{x:0>4} writes={d} last_value=0x{x:0>8} ever_nonzero={s} last_write_seq={d}\n",
            .{ record.register, record.writes, record.last_value, if (record.ever_nonzero) "YES" else "NO", record.last_step },
        );
    }
}

pub fn refreshDrawDispatch(self: anytype) void {
    const scaffold = &self.gpu_draw_dispatch;
    const at = self.executed_steps;

    if (!self.gpu_draw_dispatch_configured) {
        self.gpu_draw_dispatch_configured = true;
        scaffold.policy = drawDispatchPolicyFromEnvironment();
        if (scaffold.policy != .observe_only) {
            machoCapturePrint(
                "macho-processor: DRAW DISPATCH: policy={s} selected by ROSETTE_DRAW_DISPATCH. Rosette may now deliver queued GPU completions the emulator did not. Every delivery is recorded as a substitution and none of them closes the authentic dispatch stage, so a run that only advanced because of this still reads as a title that never received its own completion\n",
                .{scaffold.policy.label()},
            );
        }
    }

    // The strongest source: Rosette intercepted the registration call and
    // watched the guest hand the address over.
    if (self.gpu_interrupt_callback != 0) {
        scaffold.observeCallback(
            self.gpu_interrupt_callback,
            self.gpu_interrupt_callback_arg,
            .intercepted_binding,
            .translated_x86,
            at,
        );
    }
    // The weakest: parsed out of an emulator diagnostic line. Recorded at
    // its true strength so a policy can refuse it.
    const transaction = &self.interrupt_callback_transaction;
    if (transaction.callback_address != 0) {
        scaffold.observeCallback(
            transaction.callback_address,
            transaction.user_data,
            .emulator_log_claim,
            .xenia_powerpc,
            at,
        );
    }
    scaffold.observeQueued(self.gpu_xenos_runtime.draw_completion_signals);

    // Supply a front buffer when nothing else can name one. The address is
    // the guest front-buffer window the console reserves; the extent is the
    // mode this display path negotiates. Refused if implausible, because
    // the command processor asserts on an extent it cannot use.
    if (scaffold.policy != .observe_only and
        scaffold.suppliedSurface() == null and
        self.gpu_frontbuffer == null and
        !self.gpu_vd_swap_contract.frontbufferKnown())
    {
        if (self.gpu_ring_watch_base != 0) {
            if (scaffold.supplySurface(
                gpu.draw_dispatch.default_frontbuffer_address,
                gpu.draw_dispatch.default_width,
                gpu.draw_dispatch.default_height,
                .frontbuffer_never_named,
                at,
            )) {
                machoCapturePrint(
                    "macho-processor: DRAW DISPATCH: supplied a front buffer at 0x{x:0>8} {d}x{d} because no source ever named one. This surface is Rosette's and is tagged as such permanently: a frame presented from it is never guest output, and the substitution ladder can now take its lowest rung without inventing a swap\n",
                    .{
                        gpu.draw_dispatch.default_frontbuffer_address,
                        gpu.draw_dispatch.default_width,
                        gpu.draw_dispatch.default_height,
                    },
                );
            }
        }
    }

    // Attribute an effect to the most recent delivery. Only a delivery can
    // carry one, and only once.
    if (scaffold.last.outcome == .delivered and scaffold.last.effect == .unmeasured) {
        const contract_ledger = &self.gpu_vd_swap_contract;
        const effect: gpu.DrawDispatchEffect = if (contract_ledger.observed(.authentic_xe_swap_consumed))
            .present_reached
        else if (self.gpu_ring_publication.advances > 1 and
            self.gpu_ring_publication.last_advance_step > scaffold.last.step)
            .producer_published
        else if (contract_ledger.observed(.guest_producer_progressed_after_draw))
            .guest_progressed
        else if (self.executed_steps -| scaffold.last.step > effect_settle_steps)
            .no_observable_change
        else
            .unmeasured;
        if (effect != .unmeasured) scaffold.noteEffect(effect);
    }
}

pub fn drawDispatchPolicyFromEnvironment() gpu.DrawDispatchPolicy {
    const raw = std.c.getenv("ROSETTE_DRAW_DISPATCH") orelse return .observe_only;
    const value = std.mem.span(raw);
    if (std.mem.eql(u8, value, "bound")) return .bound_callbacks_only;
    if (std.mem.eql(u8, value, "guest")) return .guest_addressed;
    if (std.mem.eql(u8, value, "any")) return .any_known_address;
    return .observe_only;
}

pub fn logDrawDispatch(self: anytype) void {
    self.refreshDrawDispatch();
    const scaffold = &self.gpu_draw_dispatch;
    const totals = scaffold.summary();
    const finding = totals.finding();

    machoCapturePrint(
        "macho-processor: DRAW DISPATCH: finding={s} policy={s} callback=0x{x:0>8} address_space={s} executor=translated-x86 provenance={s} upgrades={d} conflicts={d} queued_signals={d} attempts={d} delivered={d} failures={d} refused(no_callback/unverified/cross_domain/policy)={d}/{d}/{d}/{d} completions_delivered={d} effects(inert/advancing)={d}/{d} surface_supplied={s} step={d}; {s}\n",
        .{
            finding.label(),
            totals.policy.label(),
            totals.callback.address,
            totals.callback.address_space.label(),
            totals.callback.provenance.label(),
            totals.callback.upgrades,
            totals.callback.conflicts,
            self.gpu_xenos_runtime.draw_completion_signals,
            totals.attempts,
            totals.delivered,
            totals.failures,
            totals.refused_no_callback,
            totals.refused_unverified,
            totals.refused_cross_domain,
            totals.refused_by_policy,
            totals.completions_delivered,
            totals.inert_deliveries,
            totals.advancing_deliveries,
            if (totals.surface_supplied) "YES" else "NO",
            self.executed_steps,
            finding.guidance(),
        },
    );
    const authentic = &self.interrupt_callback_transaction;
    machoCapturePrint(
        "  CALLBACK DOMAIN SPLIT: retained_draws_observed={d} model_signals_published={d} model_executor=translated-x86; xenia_powerpc(callback/registrations/attempts/returns/skips/deferrals)=0x{x:0>8}/{d}/{d}/{d}/{d}/{d} counters_valid={s}. Xenia's returning PowerPC callback is healthy in its own executor domain and is never entered or credited by Rosette's translated-x86 scaffold\n",
        .{
            self.gpu_xenos_runtime.retained_draw_observations,
            self.gpu_xenos_runtime.draw_completion_signals,
            authentic.callback_address,
            authentic.registrations,
            authentic.dispatch_attempts,
            authentic.callback_returns,
            authentic.dispatch_skips,
            authentic.dispatch_deferrals,
            if (authentic.counterInvariantHolds()) "YES" else "NO",
        },
    );

    if (scaffold.suppliedSurface()) |surface| {
        machoCapturePrint(
            "  DRAW DISPATCH SURFACE: harness_supplied=YES address=0x{x:0>8} extent={d}x{d} reason={s} step={d}; a frame presented from this surface is Rosette's and is never counted as guest output\n",
            .{
                surface.description.frontbuffer_physical_address,
                surface.description.width,
                surface.description.height,
                surface.reason.label(),
                surface.supplied_step,
            },
        );
    }

    for (scaffold.recent[0..scaffold.recent_count]) |attempt| {
        machoCapturePrint(
            "  dispatch attempt outcome={s: <20} provenance={s: <20} effect={s: <22} queued_before={d} delivered={d} step={d}\n",
            .{
                attempt.outcome.label(),
                attempt.provenance.label(),
                attempt.effect.label(),
                attempt.queued_before,
                attempt.delivered_count,
                attempt.step,
            },
        );
    }
}

pub fn logWaitGraph(self: anytype) void {
    const graph = &self.wait_graph;
    // `livelockOperation` resolves each object through the process-owned
    // sync identity table before it reaches the graph. Do not fold it a
    // second time here: almost every console address is a plausible u32,
    // so the former second opinion could neither recognise a truncated host
    // pointer nor prove that an already canonical value was safe to fold.

    // The independent progress axis is refreshed by the integrity
    // observation as well as this report. Keep the call here for reports
    // emitted without a preceding integrity checkpoint, but share the
    // implementation so the two views cannot drift.
    self.refreshWaitGraphProgress();

    const totals = graph.summary();
    const continuation = graph.continuationSummary(self.executed_steps);
    const verdict = totals.verdict();
    machoCapturePrint(
        "macho-processor: WAIT GRAPH: verdict={s} self_resolving={s} objects={d} events={d} orphan(wait/signal)={d}/{d} handshakes(stalled/progressing)={d}/{d} insufficient={d} timeout_only={d} cycles={d} folds={d} dropped_objects={d} step={d}; {s}\n",
        .{
            verdict.label(),
            if (verdict.selfResolving()) "YES" else "NO",
            totals.objects,
            totals.events,
            totals.orphan_waits,
            totals.orphan_signals,
            totals.stalled_handshakes,
            totals.progressing_handshakes,
            totals.insufficient,
            totals.timeout_only,
            totals.cycles,
            totals.canonical_folds,
            totals.dropped_objects,
            self.executed_steps,
            verdict.guidance(),
        },
    );
    machoCapturePrint(
        "  WAIT CONTINUATION: pending={d} observed={d} same_site={d} transitions={d} observed_without_pc={d} observed_untrusted_pc={d} incomparable_pc={d} unobserved={d} dropped={d} out_of_order={d} unattributed={d} max_pending_age={d}; a returned wait is not treated as progress until the next ordered activity is observed, and a PC proves control flow only when its domain and quality are comparable\n",
        .{
            continuation.pending,
            continuation.observed,
            continuation.same_site,
            continuation.transitions,
            continuation.observed_without_pc,
            continuation.observed_untrusted_pc,
            continuation.incomparable_pc,
            continuation.unobserved,
            continuation.dropped,
            continuation.out_of_order,
            continuation.unattributed,
            continuation.max_pending_age,
        },
    );

    // The graph describes the observed shape; the package decides what
    // Rosette may safely do with that shape. Keep this decision beside the
    // graph snapshot so a stale timeout audit cannot accidentally authorize
    // a park, resume, or guest synthetic wake.
    var policy_cautions: usize = 0;
    var policy_faults: usize = 0;
    var policy_actionable: usize = 0;
    for (graph.objects) |record| {
        if (!record.occupied) continue;
        const policy_decision = record.policyDecision();
        if (policy_decision.severity == .caution) policy_cautions += 1;
        if (policy_decision.requires_fault) policy_faults += 1;
        if (policy_decision.classification != .unobserved and
            policy_decision.classification != .handshake_progressing)
        {
            policy_actionable += 1;
        }
    }
    machoCapturePrint(
        "  WAIT HANDSHAKE POLICY: actionable={d} cautions={d} faults={d} timeout_only={d} guest_synthetic_wake=REFUSED step={d}; timeout-only attempts stay out of parked-consumer accounting, and only the POSIX scheduler recovery path can request a bounded spurious recheck\n",
        .{ policy_actionable, policy_cautions, policy_faults, totals.timeout_only, self.executed_steps },
    );
    for (graph.objects) |record| {
        if (!record.occupied) continue;
        const policy_decision = record.policyDecision();
        if (policy_decision.classification == .unobserved or
            policy_decision.classification == .handshake_progressing)
        {
            continue;
        }
        machoCapturePrint(
            "  wait policy object=0x{x:0>8} kind={s} timeout_class={s} timeout_ms={d} timeout_requested_known={s} timeout_requested={s} classification={s} action={s} severity={s} may_resume={s} may_synthesize_wake={s} waits={d} successful={d} returned={d} timeouts={d} signals={d}; {s}\n",
            .{
                record.address,
                record.object_kind.label(),
                record.timeout_class.label(),
                record.timeout_ms,
                if (record.timeout_requested_known) "YES" else "NO",
                if (record.timeout_requested) "YES" else "NO",
                policy_decision.classification.label(),
                policy_decision.action.label(),
                policy_decision.severity.label(),
                if (policy_decision.may_resume) "YES" else "NO",
                if (policy_decision.may_synthesize_wake) "YES" else "NO",
                record.waits,
                record.successful_waits,
                record.completed_successes,
                record.timed_out_waits,
                record.signals,
                policy_decision.guidance(),
            },
        );
    }
    machoCapturePrint(
        "  WAIT GRAPH PAIRING: pending(active/capacity)={d}/{d} dropped={d} unmatched_results={d} identity_conflicts={d}; explicit result identities outrank compatibility breadcrumbs and missing pairs are not guessed\n",
        .{
            self.livelock_pending_wait_active,
            guest_log.pending_wait_capacity,
            self.livelock_pending_wait_dropped,
            self.livelock_pending_wait_unmatched_results,
            self.livelock_pending_wait_identity_conflicts,
        },
    );

    if (totals.cycle) |cycle| {
        machoCapturePrint(
            "  WAIT CYCLE: thread 0x{x} waits on 0x{x} which only thread 0x{x} signals, and thread 0x{x} waits on 0x{x} which only thread 0x{x} signals. Neither can proceed and neither is idle\n",
            .{
                cycle.first_thread,
                cycle.first_object,
                cycle.second_thread,
                cycle.second_thread,
                cycle.second_object,
                cycle.first_thread,
            },
        );
    }

    if (graph.blocking()) |record| {
        machoCapturePrint(
            "  WAIT GRAPH BLOCKER: object=0x{x:0>8} state={s} waits={d} signals={d} waiters={d} signallers={d} first_step={d} last_step={d} evidence(success/returned/timeout blocked/ready/unknown)={d}/{d}/{d} {d}/{d}/{d} handoff_proven={s} handoff_order={s} blocked_after_signal={d} blocked_without_prior_signal={d} last_signal_step={d} progress(first/last)={d}/{d}; {s}\n",
            .{
                record.address,
                record.state().label(),
                record.waits,
                record.signals,
                record.waiter_count,
                record.signaller_count,
                record.first_step,
                record.last_step,
                record.successful_waits,
                record.completed_successes,
                record.timed_out_waits,
                record.blocked_successes,
                record.ready_on_entry,
                record.unknown_timing,
                if (record.blockedHandoffProven()) "YES" else "NO",
                record.handoffOrder().label(),
                record.blocked_after_signal,
                record.blocked_without_prior_signal,
                record.last_signal_step,
                record.progress_at_first,
                record.progress_at_last,
                record.state().guidance(),
            },
        );
        if (record.soleWaiter()) |waiter| {
            machoCapturePrint(
                "    waiter    thread=0x{x} pc=0x{x} pc_domain={s} pc_quality={s} events={d} first_step={d} last_step={d} same_site_reentries={d} site_transitions={d} pc_untrusted={d} pc_incomparable={d}\n",
                .{ waiter.thread, waiter.pc, waiter.pc_domain.label(), waiter.pc_quality.label(), waiter.events, waiter.first_step, waiter.last_step, waiter.same_site_reentries, waiter.site_transitions, waiter.pc_untrusted_events, waiter.pc_incomparable_events },
            );
            if (graph.continuationFor(record.address, waiter.thread)) |wait_continuation| {
                machoCapturePrint(
                    "    waiter-continuation object=0x{x} thread=0x{x} state={s} timing={s} wait_pc=0x{x} wait_pc_domain={s} wait_pc_quality={s} wait_step={d} next_kind={s} next_pc=0x{x} next_pc_domain={s} next_pc_quality={s} next_step={d} age={d}; {s}\n",
                    .{
                        wait_continuation.object,
                        wait_continuation.thread,
                        wait_continuation.state.label(),
                        wait_continuation.timing.label(),
                        wait_continuation.wait_pc,
                        wait_continuation.wait_pc_domain.label(),
                        wait_continuation.wait_pc_quality.label(),
                        wait_continuation.wait_step,
                        wait_continuation.next_kind.label(),
                        wait_continuation.next_pc,
                        wait_continuation.next_pc_domain.label(),
                        wait_continuation.next_pc_quality.label(),
                        wait_continuation.next_step,
                        wait_continuation.age(self.executed_steps),
                        wait_continuation.state.guidance(),
                    },
                );
            } else {
                machoCapturePrint(
                    "    waiter-continuation object=0x{x} thread=0x{x} state=unobserved; no wait completion is retained for this participant, so no continuation conclusion is made\n",
                    .{ record.address, waiter.thread },
                );
            }
        }
        if (record.soleSignaller()) |signaller| {
            machoCapturePrint(
                "    signaller thread=0x{x} pc=0x{x} pc_domain={s} pc_quality={s} events={d} first_step={d} last_step={d} same_site_reentries={d} site_transitions={d} pc_untrusted={d} pc_incomparable={d}\n",
                .{ signaller.thread, signaller.pc, signaller.pc_domain.label(), signaller.pc_quality.label(), signaller.events, signaller.first_step, signaller.last_step, signaller.same_site_reentries, signaller.site_transitions, signaller.pc_untrusted_events, signaller.pc_incomparable_events },
            );
        }
    }

    for (graph.objects) |record| {
        if (!record.occupied) continue;
        if (!record.state().isFinding()) continue;
        machoCapturePrint(
            "  wait object 0x{x:0>8} {s: <22} waits={d: <6} signals={d: <6} waiters={d} signallers={d} dropped={d} evidence(success/returned/timeout blocked/ready/unknown)={d}/{d}/{d} {d}/{d}/{d} handoff_proven={s} progress(first/last)={d}/{d} last_step={d}\n",
            .{
                record.address,
                record.state().label(),
                record.waits,
                record.signals,
                record.waiter_count,
                record.signaller_count,
                record.participants_dropped,
                record.successful_waits,
                record.completed_successes,
                record.timed_out_waits,
                record.blocked_successes,
                record.ready_on_entry,
                record.unknown_timing,
                if (record.blockedHandoffProven()) "YES" else "NO",
                record.progress_at_first,
                record.progress_at_last,
                record.last_step,
            },
        );
    }
}

pub fn logTranslationEconomics(self: anytype) void {
    const totals = self.translation_economics.summary();
    const verdict = totals.verdict();

    machoCapturePrint(
        "macho-processor: TRANSLATION ECONOMICS: verdict={s} converges={s} fills={d} causes(vacant/conflict/cold/stale/flush)={d}/{d}/{d}/{d}/{d} conflict={d}% recoverable={d} invalidations(precise/wholesale)={d}/{d} invalidated_bytes={d} sampled_pages={d} unsampled_events={d} sample_complete={s} step={d}; {s}\n",
        .{
            verdict.label(),
            if (verdict.converges()) "YES" else "NO",
            totals.decodes,
            totals.vacant_fills,
            totals.conflict_fills,
            totals.cold_evictions,
            totals.stale_refills,
            totals.flush_refills,
            totals.conflictPercent(),
            totals.recoverableDecodes(),
            totals.precise_invalidations,
            totals.wholesale_flushes,
            totals.invalidated_bytes,
            totals.sampled_pages,
            totals.unsampled_events,
            if (totals.sampleComplete()) "YES" else "NO",
            self.executed_steps,
            verdict.guidance(),
        },
    );

    // One row per miss class, with the policy that governs it.
    //
    // A single `misses=911150 hit_rate=99%` is not judgeable: it merges the
    // compulsory first touches, which no cache can avoid, with cold
    // working-set evictions and the classes that prove reusable loss. The
    // reader has to be able to see which is which and what each one costs,
    // without knowing the taxonomy beforehand.
    var compulsory_misses: u64 = 0;
    var deferred_misses: u64 = 0;
    var actionable_misses: u64 = 0;
    var fail_fast_misses: u64 = 0;
    inline for (@typeInfo(translation_economics.Cause).@"enum".fields) |field| {
        const cause: translation_economics.Cause = @enumFromInt(field.value);
        const count: u64 = switch (cause) {
            .vacant_fill => totals.vacant_fills,
            .capacity_conflict => totals.conflict_fills,
            .cold_eviction => totals.cold_evictions,
            .stale_bytes => totals.stale_refills,
            .flush_collateral => totals.flush_refills,
        };
        if (cause.compulsory()) {
            compulsory_misses +|= count;
        } else if (cause.recurring()) {
            actionable_misses +|= count;
        } else {
            deferred_misses +|= count;
        }
        if (cause.requiresFailFast()) fail_fast_misses +|= count;
        machoCapturePrint(
            "  translation miss {s: <18} count={d: <10} share={d}% fatal={s} {s}\n",
            .{
                cause.label(),
                count,
                translation_economics.percentage(count, totals.decodes),
                if (cause.requiresFailFast()) "YES" else "NO",
                cause.policy(),
            },
        );
    }
    machoCapturePrint(
        "  translation miss accounting: compulsory={d} deferred_cold={d} actionable_recurring={d} fatal_on_strict_fault={d} of {d}; every fill the cache could have avoided arms the strict fault hook and a compulsory first touch never does, while the cause classes stay separate: compulsory is first-touch work, cold is never-reused working-set evidence, and conflicts/stale/flush are avoidable loss\n",
        .{ compulsory_misses, deferred_misses, actionable_misses, fail_fast_misses, totals.decodes },
    );

    // The hit rate is independent of why the misses occurred. Keep it next
    // to the cause ledger, but do not infer mutation from either number.
    const cache_total = self.decode_cache_hits + self.decode_cache_misses;
    const hit_percent: u64 = if (cache_total == 0) 0 else (self.decode_cache_hits * 100) / cache_total;
    machoCapturePrint(
        "  translation cache: entries={d} ways={d} sets={d} hits={d} misses={d} hit_rate={d}% miss(vacant/conflict/cold)={d}/{d}/{d} stale_byte_rejections={d} victim(hits/fills/stale)={d}/{d}/{d} static_l2(entries/hits/fills)={d}/{d}/{d}\n",
        .{
            self.decode_cache.len,
            constants.DECODE_CACHE_WAYS,
            constants.DECODE_CACHE_SET_COUNT,
            self.decode_cache_hits,
            self.decode_cache_misses,
            hit_percent,
            self.decode_cache_vacant_misses,
            self.decode_cache_conflict_misses,
            self.decode_cache_cold_eviction_misses,
            self.decode_cache_stale_rejections,
            self.decode_cache_victim_hits,
            self.decode_cache_victim_fills,
            self.decode_cache_victim_stale_rejections,
            self.static_decode_l2.len,
            self.static_decode_l2_hits,
            self.static_decode_l2_fills,
        },
    );
    machoCapturePrint("  translation domains: static(h/m/f)={d}/{d}/{d} dynamic={d}/{d}/{d} thunk={d}/{d}/{d} unknown={d}/{d}/{d}; banks are disjoint\n", .{
        self.decode_domain_hits[translation_domain.Domain.static_image.bank()],
        self.decode_domain_misses[translation_domain.Domain.static_image.bank()],
        self.decode_domain_fills[translation_domain.Domain.static_image.bank()],
        self.decode_domain_hits[translation_domain.Domain.dynamic_generated.bank()],
        self.decode_domain_misses[translation_domain.Domain.dynamic_generated.bank()],
        self.decode_domain_fills[translation_domain.Domain.dynamic_generated.bank()],
        self.decode_domain_hits[translation_domain.Domain.thunk_bridge.bank()],
        self.decode_domain_misses[translation_domain.Domain.thunk_bridge.bank()],
        self.decode_domain_fills[translation_domain.Domain.thunk_bridge.bank()],
        self.decode_domain_hits[translation_domain.Domain.unknown.bank()],
        self.decode_domain_misses[translation_domain.Domain.unknown.bank()],
        self.decode_domain_fills[translation_domain.Domain.unknown.bank()],
    });
    // Occupancy, not fills. Fills only ever grow, so a bank that is full
    // and a bank that filled once and was invalidated read the same. This
    // row is the one that says whether a bank is about to start evicting,
    // and whether the capacity it was given matches the work it is doing.
    var occupancy: [translation_domain.count]BankOccupancy = undefined;
    for (translation_domain.all) |domain| {
        occupancy[domain.bank()] = self.sampleBankOccupancy(domain);
    }
    machoCapturePrint(
        "  translation bank occupancy: static={d}%({d}/{d}) dynamic={d}%({d}/{d}) thunk={d}%({d}/{d}) unknown={d}%({d}/{d}) sampled_sets={d}/{d}/{d}/{d}; banks are sized by measured demand, so an uneven row is the routing working rather than an unfair split — read it against the fill census above, because fills never come back down and occupancy does\n",
        .{
            occupancy[0].percent(),    occupancy[0].estimated(),  occupancy[0].capacity,
            occupancy[1].percent(),    occupancy[1].estimated(),  occupancy[1].capacity,
            occupancy[2].percent(),    occupancy[2].estimated(),  occupancy[2].capacity,
            occupancy[3].percent(),    occupancy[3].estimated(),  occupancy[3].capacity,
            occupancy[0].sampled_sets, occupancy[1].sampled_sets, occupancy[2].sampled_sets,
            occupancy[3].sampled_sets,
        },
    );

    if (totals.hottest_recurring != 0) {
        var hottest: [25]translation_economics.PageRecord = undefined;
        const found = self.translation_economics.hottestPages(&hottest);
        machoCapturePrint(
            "  TRANSLATION PRESSURE HOTSPOTS: {d} sampled page(s) with recurring fill cost; conflicts are reused-entry eviction evidence, cold evictions are reported separately, and stale refills are byte-change evidence. `witnesses` names concrete conflicting addresses inside the page and `dispersed` says whether there were more than the sample holds: a handful of addresses evicting each other is an indexing problem, and a page full of them is a working set that does not fit\n",
            .{found},
        );
        for (hottest[0..found]) |record| {
            const record_domain = self.translationDomainFor(record.conflict_address);
            const record_set_bases = self.decodeCacheSetBasesFor(record.conflict_address, record_domain);
            machoCapturePrint(
                "  cache-pressure page=0x{x:0>12} fills={d} vacant={d} conflicts={d} cold={d} stale={d} flush={d} distinct_byte_addresses={d} dispersed={s} witness=0x{x} set_candidates={d}/{d} symbol={s}+0x{x} first_step={d} last_step={d}\n",
                .{
                    record.page << translation_economics.page_shift,
                    record.decodes,
                    record.vacant_fills,
                    record.conflict_fills,
                    record.cold_evictions,
                    record.stale_refills,
                    record.flush_refills,
                    record.distinct_conflict_addresses,
                    if (record.conflictsAreDispersed()) "YES" else "NO",
                    record.conflict_address,
                    // Both primary choices are reported. A single set
                    // number would make a healthy alternate placement
                    // look like a conflict in the strict-run evidence.
                    record_set_bases[0] / constants.DECODE_CACHE_WAYS,
                    record_set_bases[1] / constants.DECODE_CACHE_WAYS,
                    if (self.metadata.nearestSymbol(record.conflict_address)) |symbol| symbol.name else "<unsymbolized>",
                    if (self.metadata.nearestSymbol(record.conflict_address)) |symbol| symbol.offset else 0,
                    record.first_step,
                    record.last_step,
                },
            );
            // The other addresses this page evicted, when there is more
            // than one. A single witness is already on the line above.
            const witnesses = record.witnesses();
            if (witnesses.len > 1) {
                for (witnesses[1..]) |address| {
                    const witness_domain = self.translationDomainFor(address);
                    const witness_set_bases = self.decodeCacheSetBasesFor(address, witness_domain);
                    machoCapturePrint(
                        "    cache-pressure witness=0x{x} set_candidates={d}/{d} symbol={s}+0x{x}\n",
                        .{
                            address,
                            witness_set_bases[0] / constants.DECODE_CACHE_WAYS,
                            witness_set_bases[1] / constants.DECODE_CACHE_WAYS,
                            if (self.metadata.nearestSymbol(address)) |symbol| symbol.name else "<unsymbolized>",
                            if (self.metadata.nearestSymbol(address)) |symbol| symbol.offset else 0,
                        },
                    );
                }
            }
        }
    }
}

pub fn logGuestLogChannels(self: anytype) void {
    const totals = self.guest_log_channels.summary();
    machoCapturePrint(
        "macho-processor: GUEST LOG CHANNELS: channels={d} gets={d} hits={d} appends={d} emitted={d} failed={d} missing_appends={d} overflow={d} isolated={s}; one 64-KiB formatting buffer is owned by each observed guest thread\n",
        .{
            totals.channels,
            totals.get_requests,
            totals.get_hits,
            totals.append_requests,
            totals.emissions,
            totals.failed_emissions,
            totals.missing_appends,
            totals.overflow,
            if (totals.isolated()) "YES" else "NO",
        },
    );
}

pub fn runHorizonAxisFrozen(self: anytype) bool {
    return self.gpu_ring_publication.advances != 0 and
        self.gpu_vd_swap_contract.observed(.draw_consumed) and
        !self.gpu_vd_swap_contract.observed(.guest_producer_progressed_after_draw);
}

pub fn runHorizonStalled(self: anytype) bool {
    return self.run_horizon.verdict(self.runHorizonAxisFrozen()) == .stalled;
}

pub fn logRunHorizon(self: anytype) void {
    const ledger = &self.run_horizon;
    ledger.observe(.{
        .step = self.executed_steps,
        .emulated_ms = ledger.latest.emulated_ms,
        .vblanks = ledger.latest.vblanks,
        .host_seconds = self.elapsedHostSeconds(),
    });

    // The independent axis: the producer's own publication counter. A
    // frozen axis alone never convicts — the verdict requires a long quiet
    // tail as well — but without one a quiet run cannot be called dead.
    const axis_frozen = self.runHorizonAxisFrozen();
    const verdict = ledger.verdict(axis_frozen);

    machoCapturePrint(
        "macho-processor: RUN HORIZON: verdict={s} milestones={d} last={s} progress={d}% quiet_tail={d}% step={d} emulated_ms={d} vblanks={d} host_s={d} rate={d}ms/s axis_frozen={s}; {s}\n",
        .{
            verdict.label(),
            ledger.milestones_reached,
            if (ledger.last_milestone_name.len != 0) ledger.last_milestone_name else "<none>",
            ledger.progressPercent(),
            ledger.quietTailPercent(),
            ledger.latest.step,
            ledger.latest.emulated_ms,
            ledger.latest.vblanks,
            ledger.latest.host_seconds,
            ledger.emulatedMsPerHostSecond(),
            if (axis_frozen) "YES" else "NO",
            verdict.guidance(),
        },
    );

    // The projection is what turns "run longer" from advice into a
    // decision. Four minutes and nine hours are different conversations,
    // and until the number is on the page the choice is made blind.
    inline for (.{ @as(u64, 10_000), @as(u64, 30_000), @as(u64, 60_000) }) |target| {
        const projection = ledger.project(target);
        if (projection.known()) {
            machoCapturePrint(
                "  horizon projection: reaching emulated {d}ms needs about {d} more host seconds at the {d}ms/s this run achieved\n",
                .{ target, projection.host_seconds_required orelse 0, projection.emulated_ms_per_host_second },
            );
        } else {
            machoCapturePrint(
                "  horizon projection: emulated {d}ms is unprojectable — the run produced no measurable emulated-time rate, so run length cannot be reasoned about yet\n",
                .{target},
            );
        }
    }

    for (ledger.milestones[0..ledger.milestone_count]) |milestone| {
        machoCapturePrint(
            "  milestone {s: <38} step={d: <14} emulated_ms={d: <8} vblanks={d}\n",
            .{ milestone.name, milestone.step, milestone.emulated_ms, milestone.vblanks },
        );
    }
    if (ledger.milestones_dropped != 0) {
        machoCapturePrint(
            "  RUN HORIZON: {d} milestones past the retained window; the verdict still uses the newest, the list above does not show it\n",
            .{ledger.milestones_dropped},
        );
    }
}

pub fn logVdSwapTrace(self: anytype) void {
    self.refreshVdSwapContract();
    const ledger = &self.gpu_vd_swap_contract;
    const totals = ledger.diagnosisSummary();
    const actionable = ledger.actionableMask();

    machoCapturePrint(
        "macho-processor: VD SWAP TRACE: met={d}/{d} walls={d} (findings={d} refused={d} starved={d} unprobed={d}) starved(rosette_closable/unattributed)={d}/{d} unattributed_records={d} downstream={d} probe_records={d} unlisted={d} step={d}; {s}\n",
        .{
            totals.met,
            gpu.vd_swap_contract.stage_count,
            totals.actionable + totals.starved + totals.unprobed,
            totals.actionable -| totals.refused_by_owner,
            totals.refused_by_owner,
            totals.starved,
            totals.unprobed,
            totals.starved_closable_by_rosette,
            totals.starved_unattributed,
            ledger.probes.unattributed_starvations,
            totals.blocked_upstream,
            ledger.probes.records,
            ledger.probes.unlisted_probe_records,
            self.executed_steps,
            totals.verdict(),
        },
    );

    if (ledger.primaryWall()) |wall| {
        machoCapturePrint(
            "  VD SWAP PRIMARY WALL: stage={s} chain={s} owner={s} attribution={s} decided_by={s}/{s} detail={d}; {s}\n",
            .{
                wall.stage.label(),
                wall.chain.label(),
                wall.stage.owner().label(),
                wall.attribution.label(),
                if (wall.decided_by) |which| which.label() else "<none>",
                wall.decided_outcome.label(),
                wall.detail,
                wall.attribution.guidance(),
            },
        );
        // A starved wall used to end here: a stage that has not been shown
        // false and no way to find out what would show it. The cause names
        // the missing input and who can supply it.
        if (wall.attribution == .starved) {
            machoCapturePrint(
                "  VD SWAP PRIMARY WALL STARVED: cause={s} blames={s} closable_by_rosette={s}; {s}\n",
                .{
                    wall.starvation_cause.label(),
                    wall.starvation_cause.owner().label(),
                    if (wall.starvation_cause.closableByRosette()) "YES" else "NO",
                    wall.starvation_cause.remedy(),
                },
            );
        }
    }

    // Per-chain frontiers.  A stalled producer and a fully reached
    // transport chain are both true at once, and one linear frontier can
    // only ever report the first.
    inline for (@typeInfo(gpu.VdSwapChain).@"enum".fields) |field| {
        const chain: gpu.VdSwapChain = @enumFromInt(field.value);
        const met = ledger.chainMet(chain);
        const total = gpu.vd_swap_contract.chainStageCount(chain);
        machoCapturePrint(
            "  vd-swap chain {s: <13} met={d}/{d} frontier={s: <38} owner={s: <24}; {s}\n",
            .{
                chain.label(),
                met,
                total,
                if (ledger.chainFrontier(chain)) |stage| stage.label() else "<complete>",
                if (ledger.chainFrontier(chain)) |stage| stage.owner().label() else "-",
                chain.meaning(),
            },
        );
    }

    // One line per unmet stage, in contract order, with the probes that
    // decided it.  A met stage is already covered by the stage table in
    // `logVdSwapContract`; repeating it here would bury the nineteen lines
    // this report exists to make readable.
    inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
        const stage: gpu.VdSwapStage = @enumFromInt(field.value);
        const diagnosis = ledger.diagnose(stage);
        if (diagnosis.attribution != .met) {
            machoCapturePrint(
                "  vd-swap gap {s: <38} chain={s: <13} {s: <16} owner={s: <24} wall={s: <3} blocked_by={s: <38} probes={d}/{d} evidence={d} starved={d} cause={s: <22} blames={s: <26} decided={s}/{s} detail={d}\n",
                .{
                    stage.label(),
                    diagnosis.chain.label(),
                    diagnosis.attribution.label(),
                    stage.owner().label(),
                    if (actionable & gpu.vd_swap_contract.stageBit(stage) != 0) "YES" else "NO",
                    if (diagnosis.blocked_by) |prerequisite| prerequisite.label() else "-",
                    diagnosis.probes_attempted,
                    diagnosis.probes_total,
                    diagnosis.probes_with_evidence,
                    diagnosis.probes_starved,
                    if (diagnosis.probes_starved != 0) diagnosis.starvation_cause.label() else "-",
                    if (diagnosis.probes_starved != 0) diagnosis.starvation_cause.owner().label() else "-",
                    if (diagnosis.decided_by) |which| which.label() else "<none>",
                    diagnosis.decided_outcome.label(),
                    diagnosis.detail,
                },
            );
        }
    }

    // The probe grid for the walls only.  Thirteen downstream stages times
    // sixteen probes is noise; the walls are where a reader has to know
    // exactly which evidence path came back with what.
    inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
        const stage: gpu.VdSwapStage = @enumFromInt(field.value);
        const diagnosis = ledger.diagnose(stage);
        if (diagnosis.actionable()) {
            inline for (@typeInfo(gpu.VdSwapProbe).@"enum".fields) |probe_field| {
                const which: gpu.VdSwapProbe = @enumFromInt(probe_field.value);
                {
                    if (probeSuppliesStage(stage, which)) {
                        const cell = ledger.probes.cell(stage, which);
                        machoCapturePrint(
                            "    probe {s: <38} {s: <30} {s: <18} latest={s: <18} attempts={d} evidence={d} starved={d} cause={s: <22} unattributed={d} first_starved={d} detail={d} first={d} last={d}\n",
                            .{
                                stage.label(),
                                which.label(),
                                cell.outcome.label(),
                                cell.latest.label(),
                                cell.attempts,
                                cell.evidence_attempts,
                                cell.starved_attempts,
                                if (cell.starved_attempts != 0) cell.starvation_cause.label() else "-",
                                cell.unattributed_starvations,
                                cell.first_starved_step,
                                cell.detail,
                                cell.first_step,
                                cell.last_step,
                            },
                        );
                    }
                }
            }
        }
    }

    machoCapturePrint(
        "  VD SWAP EXECUTOR: retained(executions/refusals/partial_tails)={d}/{d}/{d} span_epoch={s}{d} payload_epoch={s}{d} publication_advances={d} batches={d} ring_dwords_consumed={d} packet_errors={d}; the stateful command processor is the only source of render-target registers, EDRAM resolves and draw-completion events. Zero executions means every stage below it is unobserved rather than false\n",
        .{
            self.gpu_xenos_retained_executions,
            self.gpu_xenos_retained_refusals,
            self.gpu_xenos_runtime.retained_truncated_tails,
            // An unset epoch is a sentinel, and printing it as
            // 18446744073709551615 made a "never ran" read as a number a
            // reader could compare against something.
            if (self.gpu_xenos_last_ring_epoch == std.math.maxInt(u64)) "unset:" else "",
            if (self.gpu_xenos_last_ring_epoch == std.math.maxInt(u64)) 0 else self.gpu_xenos_last_ring_epoch,
            if (self.gpu_xenos_last_payload_epoch == std.math.maxInt(u64)) "unset:" else "",
            if (self.gpu_xenos_last_payload_epoch == std.math.maxInt(u64)) 0 else self.gpu_xenos_last_payload_epoch,
            self.gpu_ring_publication.advances,
            self.gpu_xenos_runtime.batches,
            self.gpu_xenos_runtime.ring_dwords_consumed,
            self.gpu_xenos_runtime.packet_errors,
        },
    );
    // Whether the executor followed the same indirect references the
    // walker did. The nested draws and most render-target programming live
    // behind INDIRECT_BUFFER packets, so an executor that decoded the root
    // and followed none of them has a complete-looking batch and an empty
    // register file — and nothing else in the report distinguishes that
    // from a title that programmed nothing.
    const runtime = &self.gpu_xenos_runtime;
    machoCapturePrint(
        "  VD SWAP EXECUTOR INDIRECT: buffers={d} dwords(requested/read)={d}/{d} unreadable={d} truncated={d} invalid={d} depth_limited={d} budget_limited={d} cycles={d} last_status={s} last_address=0x{x:0>8}; the walker's reference count and this one describe the same packets. They differing is a finding about which observer is looking\n",
        .{
            runtime.indirect_buffers,
            runtime.indirect_dwords_requested,
            runtime.indirect_dwords_read,
            runtime.indirect_unreadable,
            runtime.indirect_truncated,
            runtime.indirect_invalid,
            runtime.indirect_depth_limited,
            runtime.indirect_budget_limited,
            runtime.indirect_cycles,
            runtime.indirect_last_status.label(),
            runtime.indirect_last_address,
        },
    );
    if (self.gpu_xenos_runtime.retained_truncated_tails != 0) {
        machoCapturePrint(
            "  VD SWAP EXECUTOR: {d} retained batch(es) had a last packet the window did not hold, and the packets before the cut were kept. Every register and draw below comes from a partial reading of those batches — enough to judge what was programmed, and not enough to claim the batch was complete\n",
            .{self.gpu_xenos_runtime.retained_truncated_tails},
        );
    }
    self.logNewPm4Fault();
}

pub fn logNewPm4Fault(self: anytype) void {
    const fault = self.gpu_xenos_runtime.executor.fault_journal.latest() orelse return;
    if (fault.sequence <= self.gpu_pm4_last_fault_logged) return;
    self.gpu_pm4_last_fault_logged = fault.sequence;
    machoCapturePrint(
        "macho-processor: PM4 FAULT: sequence={d} packet_sequence={d} reason={s} source={s} depth={d} base=0x{x:0>8} address=0x{x:0>8} dword_offset={d} header=0x{x:0>8} kind={s} opcode={s}(0x{x:0>2}) declared_payload={d} required={d} available={d} missing={d} journal(total/retained/overwritten)={d}/{d}/{d}\n",
        .{
            fault.sequence,
            fault.packet_sequence,
            fault.reason.label(),
            fault.source.label(),
            fault.depth,
            fault.base_address,
            fault.address,
            fault.dword_offset,
            fault.raw_header,
            @tagName(fault.kind),
            fault.opcodeLabel(),
            @intFromEnum(fault.opcode),
            fault.declared_payload_dwords,
            fault.required_total_dwords,
            fault.available_dwords,
            fault.missingDwords(),
            self.gpu_xenos_runtime.executor.fault_journal.total,
            self.gpu_xenos_runtime.executor.fault_journal.count,
            self.gpu_xenos_runtime.executor.fault_journal.overwritten,
        },
    );
}

pub fn probeSuppliesStage(stage: gpu.VdSwapStage, which: gpu.VdSwapProbe) bool {
    for (gpu.vd_swap_contract.probesFor(stage)) |listed| {
        if (listed == which) return true;
    }
    return false;
}

pub fn logVdSwapContract(self: anytype) void {
    self.refreshVdSwapContract();
    // Two callers reach this inside one checkpoint. The refresh above is
    // idempotent and still runs; the twenty-nine stage lines print once.
    if (self.vd_swap_contract_report_epoch == self.report_epoch) return;
    self.vd_swap_contract_report_epoch = self.report_epoch;
    const ledger = &self.gpu_vd_swap_contract;
    const frontier = ledger.frontier();
    // A stage that has been observed and stays observed is settled. It
    // prints in full on the checkpoint that changes the observed set and is
    // collapsed to a count on every checkpoint that does not.
    const stage_established = self.vd_swap_detail_mask == ledger.observed_mask;
    self.vd_swap_detail_mask = ledger.observed_mask;
    var source_buffer: [512]u8 = undefined;
    const sources = ledger.sourceNames(&source_buffer);
    var offset_buffer: [32]u8 = undefined;
    const packet_offset = if (ledger.last_packet_offset) |offset|
        std.fmt.bufPrint(&offset_buffer, "{d}", .{offset}) catch "?"
    else
        "<none>";
    machoCapturePrint(
        "macho-processor: VD SWAP CONTRACT: met={d}/{d} frontier={s} owner={s} blocker={s} sources={s} step={d} calls={d} args={d} candidates={d} invalid={d} conflicts={d} support(geometry/projection/stream/validated/indirects/candidates)={d}/{d}/{d}/{d}/{d}/{d} packets(readable/decoded/authentic/malformed)={d}/{d}/{d}/{d} packet_candidates(seen/readable/decoded/fetch_decoded/auth_missing)={d}/{d}/{d}/{d}/{d}\n",
        .{
            frontier.met,
            frontier.total,
            if (frontier.stage) |stage| stage.label() else "<complete>",
            frontier.owner.label(),
            frontier.blocker.label(),
            if (sources.len != 0) sources else "<none>",
            self.executed_steps,
            ledger.vdswap_calls,
            ledger.arguments_observed,
            ledger.candidate_count,
            ledger.invalid_candidate_count,
            ledger.frontbuffer_conflicts,
            ledger.ring_geometry_observations,
            ledger.projection_readable_observations,
            ledger.stream_observations,
            ledger.stream_validation_observations,
            ledger.indirect_resolution_observations,
            ledger.candidate_observations,
            ledger.readable_packet_observations,
            ledger.decoded_packet_observations,
            ledger.authentic_consumptions,
            ledger.malformed_packets,
            ledger.candidate_observations,
            ledger.readable_packet_observations,
            ledger.decoded_packet_observations,
            ledger.fetch_decoded_observations,
            ledger.authentic_missing_descriptions,
        },
    );
    machoCapturePrint(
        "  VD SWAP CONTRACT DETAIL: packet_anomalies(truncated/desync)={d}/{d} PM4(root/nested/indirect/draw/swap)={d}/{d}/{d}/{d}/{d} dwords(examined/scanned/span)={d}/{d}/{d} packet_offset={s}; {s}\n",
        .{
            ledger.truncated_observations,
            ledger.desynchronised_observations,
            ledger.root_packets,
            ledger.nested_packets,
            ledger.indirect_packets,
            ledger.draw_packets,
            ledger.swap_packets,
            ledger.dwords_examined,
            ledger.dwords_scanned,
            ledger.span_dwords,
            packet_offset,
            frontier.blocker.guidance(),
        },
    );
    machoCapturePrint(
        "  VD SWAP INTERMEDIARY: PM4(state/submitted/consumed)={s}/{s}/{s} render_target(state/memory)={s}/{s} completion(signaled/dispatched)={s}/{s} guest(wait_after_draw/progress_after_draw)={s}/{s} observations={d}\n",
        .{
            if (ledger.observed(.pm4_state_programmed)) "YES" else "NO",
            if (ledger.observed(.draw_submitted)) "YES" else "NO",
            if (ledger.observed(.draw_consumed)) "YES" else "NO",
            if (ledger.observed(.render_target_state_observed)) "YES" else "NO",
            if (ledger.observed(.render_target_memory_observed)) "YES" else "NO",
            if (ledger.observed(.draw_completion_signaled)) "YES" else "NO",
            if (ledger.observed(.draw_completion_dispatched)) "YES" else "NO",
            if (ledger.observed(.guest_wait_observed_after_draw)) "YES" else "NO",
            if (ledger.observed(.guest_producer_progressed_after_draw)) "YES" else "NO",
            ledger.intermediary_observations,
        },
    );
    const target = self.gpu_xenos_runtime.renderTargetEvidence();
    machoCapturePrint(
        "  XENOS TARGET EVIDENCE: state={s} plausible={s} output_ready={s} color(base_tile/format)={d}/{d} depth(base_tile/format)={d}/{d} surface(pitch/msaa/mask)={d}/{d}/{d} raw(color/depth/surface)=0x{x:0>8}/0x{x:0>8}/0x{x:0>8}\n",
        .{
            if (target.state_observed) "YES" else "NO",
            if (target.plausible) "YES" else "NO",
            if (target.outputReady()) "YES" else "NO",
            target.color_base_tiles,
            target.color_format,
            target.depth_base_tiles,
            target.depth_format,
            target.surface_pitch_pixels,
            target.msaa_mode,
            target.color_mask,
            target.raw_color_info,
            target.raw_depth_info,
            target.raw_surface_info,
        },
    );
    machoCapturePrint(
        "  XENOS COMPLETION EVIDENCE: renderable_draws={d} draw_signals={d} draw_dispatch(attempts/success/failures)={d}/{d}/{d} color_resolves={d} causal_post_draw(wait/signal)={d}/{d}; a raw draw packet is not a frame until target-backed output and owner boundaries are observed\n",
        .{
            self.gpu_xenos_runtime.renderable_draw_observations,
            self.gpu_xenos_runtime.draw_completion_signals,
            self.gpu_draw_completion_dispatch_attempts,
            self.gpu_draw_completion_dispatches,
            self.gpu_draw_completion_dispatch_failures,
            self.gpu_xenos_runtime.color_resolve_observations,
            self.xenia_gpu_causal_trace.wait_events_after_draw,
            self.xenia_gpu_causal_trace.signal_events_after_draw,
        },
    );
    machoCapturePrint(
        "  vd-swap provenance: entry_buffer_ptr=0x{x:0>8} entry_fetch_ptr=0x{x:0>8} entry_frontbuffer_ptr=0x{x:0>8} encoded_buffer_phys=0x{x:0>8} encoded_packet_dword={d} encoded_packet_dwords={d} encoded_geometry={s} encoding_mismatches={d}\n",
        .{
            ledger.arguments.command_buffer,
            ledger.arguments.fetch_pointer,
            ledger.arguments.frontbuffer_pointer,
            ledger.encoded_command_buffer,
            ledger.encoded_packet_offset,
            ledger.encoded_packet_dwords,
            if (ledger.encoded_packet_geometry_observed) "YES" else "NO",
            ledger.packet_encoding_mismatches,
        },
    );
    var settled_stages: usize = 0;
    inline for (@typeInfo(gpu.VdSwapStage).@"enum".fields) |field| {
        const stage: gpu.VdSwapStage = @enumFromInt(field.value);
        const record = ledger.observation(stage);
        if (record.seen and stage_established) {
            settled_stages += 1;
        } else machoCapturePrint(
            "  vd-swap stage={s: <38} state={s: <3} owner={s: <28} count={d} first={d} last={d} source_mask=0x{x}\n",
            .{
                stage.label(),
                if (record.seen) "YES" else "NO",
                stage.owner().label(),
                record.count,
                record.first_step,
                record.last_step,
                record.source_mask,
            },
        );
    }
    if (settled_stages != 0) machoCapturePrint(
        "  vd-swap collapsed: {d} observed stage(s) unchanged since the previous checkpoint and printed in full there. Every unobserved stage is still listed above; this block reprints entirely the moment the observed set moves\n",
        .{settled_stages},
    );
    if (ledger.active_frontbuffer) |swap| {
        machoCapturePrint(
            "  vd-swap frontbuffer active=0x{x:0>8} extent={d}x{d} source={s} plausible={s} packet_offset={s}\n",
            .{
                swap.frontbuffer_physical_address,
                swap.width,
                swap.height,
                ledger.active_frontbuffer_source.label(),
                if (ledger.frontbufferKnown()) "YES" else "NO",
                packet_offset,
            },
        );
    } else {
        machoCapturePrint(
            "  vd-swap frontbuffer active=<none> arguments={s} fetch={s}\n",
            .{ if (ledger.arguments.frontbuffer != null) "YES" else "NO", if (ledger.arguments.fetch != null) "YES" else "NO" },
        );
    }
    for (ledger.candidates[0..ledger.candidate_count]) |candidate| {
        if (candidate.description) |swap| machoCapturePrint(
            "  vd-swap candidate source={s} address=0x{x:0>8} extent={d}x{d} plausible={s} observations={d} first_step={d}\n",
            .{
                candidate.source.label(),
                swap.frontbuffer_physical_address,
                swap.width,
                swap.height,
                if (candidate.plausible) "YES" else "NO",
                candidate.observations,
                candidate.first_step,
            },
        );
    }
}

pub fn logKernelSurface(self: anytype) void {
    const surface = &self.gpu_kernel_surface;
    const finding = surface.finding();
    const complete = surface.allImportedUsable();
    const detail_fingerprint = surface.detailFingerprint();
    const stable_complete = complete and self.kernel_surface_complete and
        self.kernel_surface_detail_fingerprint == detail_fingerprint;
    self.kernel_surface_complete = complete;
    self.kernel_surface_detail_fingerprint = detail_fingerprint;

    if (stable_complete) {
        self.kernel_surface_collapsed +|= 1;
        machoCapturePrint(
            "macho-processor: KERNEL SURFACE: imported={d} usable={d} unpopulated_imported={d} blocking=<none> complete=YES step={d}; complete imported surface is unchanged, so the per-export table was printed earlier and is collapsed (collapse_count={d})\n",
            .{
                finding.imported_count,
                finding.usable_count,
                finding.unpopulated_imported,
                self.executed_steps,
                self.kernel_surface_collapsed,
            },
        );
        return;
    }

    machoCapturePrint(
        "macho-processor: KERNEL SURFACE: imported={d} usable={d} unpopulated_imported={d} invalid_imported={d} complete={s} blocking={s} step={d}; {s}\n",
        .{
            finding.imported_count,
            finding.usable_count,
            finding.unpopulated_imported,
            finding.invalid_imported,
            if (complete) "YES" else "NO",
            if (finding.blocking) |which| which.name() else "<none>",
            self.executed_steps,
            if (finding.blocking) |which|
                which.guidance()
            else
                "every required kernel export the title imported holds a usable value; an absent frame is not explained by this surface",
        },
    );
    inline for (@typeInfo(gpu.KernelExport).@"enum".fields) |field| {
        const which: gpu.KernelExport = @enumFromInt(field.value);
        if (surface.imported(which) or which.isVariable()) machoCapturePrint(
            "  export 0x{x:0>3} {s: <12} {s: <9} {s}{s}\n",
            .{
                which.ordinal(),
                surface.population(which).label(),
                if (which.isVariable()) "variable" else "function",
                which.name(),
                if (surface.imported(which))
                    ""
                else
                    " (no host binding observed; this surface watches Rosette's host import path and says nothing about the title's own XEX imports — read KERNEL VARIABLES for those)",
            },
        );
    }
    var pending: [gpu.kernel_surface.export_count]gpu.KernelExport = undefined;
    const work = surface.harnessPopulationWork(&pending);
    for (work) |which| {
        machoCapturePrint(
            "macho-processor: KERNEL SURFACE: harness population outstanding: {s} ({d} bytes at 0x{x}) — {s}\n",
            .{ which.name(), which.byteSize(), self.gpu_kernel_surface_addresses.lookup(which.ordinal()) orelse 0, which.guidance() },
        );
    }
    if (work.len == 0) return;
    machoCapturePrint(
        "macho-processor: KERNEL SURFACE: populating a kernel *variable* is supplying platform state the real kernel already wrote, which is a legitimate harness action. Entering a kernel *function* on the title's behalf is not, and is refused by the contract's owner rule\n",
        .{},
    );
}

pub fn readConsoleDword(self: anytype, console_address: u32) ?u32 {
    if (console_address == 0) return null;
    const host = self.xenia_memory_views.virtualHostAddress(console_address) orelse return null;
    const bytes = self.guestMemoryConst(host, 4) orelse return null;
    return std.mem.readInt(u32, bytes[0..4], .big);
}

pub fn readConsolePhysicalDword(self: anytype, physical_address: u32) ?u32 {
    if (physical_address == 0) return null;
    const host = self.xenia_memory_views.physicalHostAddress(physical_address) orelse return null;
    const bytes = self.guestMemoryConst(host, 4) orelse return null;
    return std.mem.readInt(u32, bytes[0..4], .big);
}

pub fn writeConsoleDword(self: anytype, console_address: u32, value: u32) bool {
    if (console_address == 0) return false;
    const host = self.xenia_memory_views.virtualHostAddress(console_address) orelse return false;
    const bytes = self.guestMemory(host, 4) orelse return false;
    std.mem.writeInt(u32, bytes[0..4], value, .big);
    return true;
}

pub fn refreshKernelVariables(self: anytype) void {
    const surface = &self.gpu_kernel_variables;
    const custody = &self.gpu_provisioning_custody;
    const at = self.executed_steps;

    // The boundary a provisioning write has to beat.  `VdInitializeEngines`
    // is the first display bring-up export the title enters, and it is the
    // point past which these variables have been read and the decision made
    // against whatever they held.  A write after this step is correct and
    // changes nothing.
    const engines = self.gpu_bootstrap.observations[@intFromEnum(gpu.Step.initialize_engines)];
    if (engines.seen) custody.noteConsumerForAll(engines.first_step);

    inline for (.{
        gpu.KernelVariable.global_device,    gpu.KernelVariable.global_xam_device,
        gpu.KernelVariable.gpu_clock_in_mhz, gpu.KernelVariable.hsio_calibration_lock,
    }) |which| {
        _ = custody.track(
            which.ordinal(),
            which.name(),
            if (which.writer().harnessMayWrite()) .console_kernel else .guest_title,
        );
        const slot_address = self.gpu_kernel_surface_addresses.lookup(which.ordinal()) orelse 0;
        if (slot_address == 0) {
            custody.noteRefusal(which.ordinal(), .address_unknown);
        } else {
            surface.observeImport(which, true, slot_address);
            if (self.readConsoleDword(slot_address)) |slot_value| {
                surface.observeSlot(which, slot_value);
                if (gpu.kernel_variables.plausiblePointer(slot_value) and
                    !gpu.kernel_variables.isUnimplementedSentinel(slot_value, which.ordinal()))
                {
                    if (self.readConsoleDword(slot_value)) |storage| {
                        surface.observeStorage(which, storage);
                        // Anything in there the harness did not write came
                        // from somewhere else.  That is how adoption and
                        // divergence are detected without a write hook on
                        // the address.
                        custody.observeStorage(which.ordinal(), storage, at);
                    }
                }
            }
        }
        self.provisionKernelVariable(which);
    }
}

pub fn provisionPlatformStateNow(self: anytype) void {
    self.gpu_provisioning_early_attempts +|= 1;
    self.refreshKernelVariables();
}

pub fn provisionKernelVariable(self: anytype, which: gpu.KernelVariable) void {
    const custody = &self.gpu_provisioning_custody;
    switch (self.gpu_kernel_variables.writeDecision(which)) {
        .refused_title_owned => custody.noteRefusal(which.ordinal(), .not_harness_owned),
        .refused_already_populated => custody.noteRefusal(which.ordinal(), .already_present),
        .allowed => |value| {
            const slot_value = self.gpu_kernel_variables.entry(which).slot_value;
            if (!self.writeConsoleDword(slot_value, value)) {
                custody.noteRefusal(which.ordinal(), .storage_unwritable);
                self.gpu_kernel_variable_write_failures +|= 1;
                machoCapturePrint(
                    "macho-processor: KERNEL VARIABLES: could not write {s} = 0x{x} at console 0x{x:0>8}; the storage the slot points at is not writable from here, so the platform state stays unsupplied and the title will read whatever is there\n",
                    .{ which.name(), value, slot_value },
                );
                return;
            }
            _ = self.gpu_kernel_variables.noteHarnessWrite(which);
            self.gpu_kernel_variable_writes +|= 1;
            custody.noteHarnessWrite(which.ordinal(), value, self.executed_steps);
            const record = custody.entry(which.ordinal());
            machoCapturePrint(
                "macho-processor: KERNEL VARIABLES: supplied {s} = 0x{x} at console 0x{x:0>8} (harness write #{d}) timing={s} guest_steps={d}. This is platform state the real kernel established before the title ran; the title owns nothing here and nothing about its behaviour has been fabricated — {s}\n",
                .{
                    which.name(),
                    value,
                    slot_value,
                    self.gpu_kernel_variable_writes,
                    if (record) |entry| entry.timing().label() else "unknown",
                    self.executed_steps,
                    which.meaning(),
                },
            );
        },
        else => {},
    }
}

pub fn logProvisioningCustody(self: anytype) void {
    const custody = &self.gpu_provisioning_custody;
    const totals = custody.summary();
    const finding = totals.finding();
    machoCapturePrint(
        "macho-processor: PROVISIONING CUSTODY: finding={s} tracked={d} provisioned={d} preboot={d} in_time={d} LATE={d} unknown={d} adopted={d} load_bearing={d} contested={d} diverged={d} unprovisioned={d} refusals={d} address_unknown_attempts={d} early_attempts={d} step={d}; {s}\n",
        .{
            finding.label(),
            totals.tracked,
            totals.provisioned,
            totals.preboot,
            totals.provisioned -| (totals.preboot + totals.late + totals.unknown_timing),
            totals.late,
            totals.unknown_timing,
            totals.adopted,
            totals.load_bearing,
            totals.contested,
            totals.diverged,
            totals.unprovisioned,
            totals.refusals,
            totals.address_unknown_attempts,
            self.gpu_provisioning_early_attempts,
            self.executed_steps,
            finding.guidance(),
        },
    );
    if (custody.blocking()) |record| {
        machoCapturePrint(
            "  PROVISIONING BLOCKER: {s} owner={s} custody={s} timing={s} divergence={s}; {s}\n",
            .{
                record.name,
                record.owner.label(),
                record.custody().label(),
                record.timing().label(),
                record.divergence().label(),
                if (record.timing().missedItsConsumer())
                    record.timing().guidance()
                else if (record.divergence() == .diverged)
                    record.divergence().guidance()
                else
                    record.last_refusal.guidance(),
            },
        );
    }
    for (custody.records[0..custody.count]) |record| {
        machoCapturePrint(
            "  custody {s: <24} owner={s: <16} {s: <20} timing={s: <16} {s: <12} harness(value/step/writes)=0x{x:0>8}/{d}/{d} owner_write(value/step)=0x{x:0>8}/{d} consumer_step={d} refusal={s} refusals={d}\n",
            .{
                record.name,
                record.owner.label(),
                record.custody().label(),
                record.timing().label(),
                record.divergence().label(),
                record.harness_value,
                record.harness_step,
                record.harness_writes,
                record.owner_value,
                record.owner_step,
                record.consumer_step orelse 0,
                record.last_refusal.label(),
                record.refusals,
            },
        );
    }
    if (custody.dropped != 0) {
        machoCapturePrint(
            "  PROVISIONING CUSTODY: {d} resources did not fit the retained window; the list above is not the whole picture\n",
            .{custody.dropped},
        );
    }
}

pub fn logKernelVariables(self: anytype) void {
    self.refreshKernelVariables();
    const surface = &self.gpu_kernel_variables;
    const finding = surface.finding();
    machoCapturePrint(
        "macho-processor: KERNEL VARIABLES: imported={d} usable={d} blocking={s} harness_writable_outstanding={d} harness_writes={d} write_failures={d} step={d}; {s}\n",
        .{
            finding.imported_count,
            finding.usable_count,
            if (finding.blocking) |which| which.name() else "<none>",
            finding.harness_writable_outstanding,
            self.gpu_kernel_variable_writes,
            self.gpu_kernel_variable_write_failures,
            self.executed_steps,
            if (finding.blocking) |which|
                which.meaning()
            else
                "no kernel variable the title imported is broken in a way the emulator caused. A variable reading zero because the title has not written it yet is reported below and is not a defect",
        },
    );
    inline for (.{
        gpu.KernelVariable.global_device,    gpu.KernelVariable.global_xam_device,
        gpu.KernelVariable.gpu_clock_in_mhz, gpu.KernelVariable.hsio_calibration_lock,
    }) |which| {
        const record = surface.entry(which);
        machoCapturePrint(
            "  variable 0x{x:0>3} {s: <20} {s: <13} writer={s: <6} slot=0x{x:0>8} -> 0x{x:0>8} storage=0x{x:0>8} bytes={d} harness_writes={d}\n",
            .{
                which.ordinal(),
                which.name(),
                record.state.label(),
                @tagName(which.writer()),
                record.slot_address,
                record.slot_value,
                record.storage_value,
                which.storageBytes(),
                record.harness_writes,
            },
        );
    }
    inline for (.{
        gpu.KernelVariable.global_device,    gpu.KernelVariable.global_xam_device,
        gpu.KernelVariable.gpu_clock_in_mhz, gpu.KernelVariable.hsio_calibration_lock,
    }) |which| {
        if (surface.entry(which).imported) {
            switch (surface.writeDecision(which)) {
                .allowed => |value| machoCapturePrint(
                    "macho-processor: KERNEL VARIABLES: harness may supply {s} = 0x{x} — {s}\n",
                    .{ which.name(), value, which.meaning() },
                ),
                else => |refusal| if (surface.entry(which).state == .storage_zero) machoCapturePrint(
                    "macho-processor: KERNEL VARIABLES: {s} reads zero and the harness will not write it: {s}\n",
                    .{ which.name(), refusal.label() },
                ),
            }
        }
    }
}

pub fn titleInterruptCallbackRegistrationObserved(self: anytype) bool {
    return self.gpu_interrupt_callback_registrations != 0 or
        self.gpu_bringup_gate.recordFor(.set_interrupt_callback).crossed() or
        self.gpu_bootstrap.seen(.graphics_interrupt_callback) or
        self.gpu_bootstrap_provenance.guestObserved(.graphics_interrupt_callback) or
        self.gpu_bootstrap_provenance.traceObserved(.graphics_interrupt_callback);
}

pub fn titleInterruptCallbackRouteProven(self: anytype) bool {
    if (self.gpu_interrupt_callback == 0 or
        !self.titleInterruptCallbackRegistrationObserved())
        return false;
    // A title callback state field is not enough when the emulator's
    // shared completion slot currently contains its host builtin. The
    // newest observed slot occupant owns the dispatch seam; permit the
    // legacy state-only path only when no slot observation exists.
    return self.gpu_interrupt_slot_writes == 0 or self.gpu_interrupt_slot_is_guest;
}

pub fn noteGpuInterruptDispatch(self: anytype) void {
    self.refreshPreinitialization();
    self.gpu_preinitialization.observe(.interrupt_callback_dispatched, self.executed_steps);
}

pub fn refreshPreinitialization(self: anytype) void {
    const ledger = &self.gpu_preinitialization;
    const at = self.executed_steps;
    const variables = &self.gpu_kernel_variables;

    if (self.xenia_memory_views.ready()) ledger.observe(.memory_view_base_discovered, at);

    // Bound means the dereference lands somewhere, not that the storage
    // holds a value. Those are different failures with different owners,
    // and collapsing them is what made an unwritten clock look like an
    // unbound slot.
    var any_slot_bound = false;
    var every_slot_bound = true;
    inline for (.{
        gpu.KernelVariable.global_device,         gpu.KernelVariable.gpu_clock_in_mhz,
        gpu.KernelVariable.hsio_calibration_lock,
    }) |which| {
        const record = variables.entry(which);
        if (record.imported) {
            if (gpu.kernel_variables.plausiblePointer(record.slot_value)) {
                any_slot_bound = true;
            } else {
                every_slot_bound = false;
            }
        }
    }
    if (any_slot_bound and every_slot_bound) ledger.observe(.kernel_variable_slots_bound, at);

    inline for (.{
        .{ gpu.KernelVariable.gpu_clock_in_mhz, gpu.PreinitElement.gpu_clock_published },
        .{ gpu.KernelVariable.hsio_calibration_lock, gpu.PreinitElement.hsio_lock_initialised },
    }) |pair| {
        const record = variables.entry(pair[0]);
        if (record.state == .populated) {
            if (record.harness_writes != 0) {
                _ = ledger.supply(pair[1], at);
            } else {
                ledger.observe(pair[1], at);
            }
        }
    }

    // Either the emulator declared a handler for the aperture's pages, or
    // an access actually arrived. The first is reachability and the second
    // is usage; usage implies reachability, so both satisfy it.
    if (self.gpu_register_aperture_reachable or
        self.gpu_register_aperture.total_reads + self.gpu_register_aperture.total_writes != 0)
    {
        ledger.observe(.register_aperture_reachable, at);
    }
    if (self.gpu_bootstrap.seen(.initialize_engines)) ledger.observe(.engines_initialised, at);
    if (self.titleInterruptCallbackRegistrationObserved()) ledger.observe(.interrupt_callback_registered, at);
    // The bootstrap ladder learns this from the emulator's log lines. The
    // tracepoint at `EmulateCPInterruptDPC` learns it from the instruction
    // pointer, and on the 2026-08-31 run it had fired a hundred and fifty
    // times while this clause still read "registered but never fired". A
    // clause a stronger observer has already satisfied must not stay unmet.
    if (self.gpu_bootstrap.seen(.graphics_interrupt_dispatch) or
        self.gpu_bringup_gate.recordFor(.emulate_cp_interrupt_dpc).crossed())
    {
        ledger.observe(.interrupt_callback_dispatched, at);
    }
    if (self.gpu_ring_watch_base != 0) ledger.observe(.ring_geometry_established, at);
    if (self.execution_tracepoints.roleEntered(.command_processor)) ledger.observe(.command_processor_running, at);
    if (variables.entry(.global_device).state == .populated) ledger.observe(.title_device_created, at);
    // Written means dwords exist, not that any of them was a draw. Keying
    // this on draws reported an ordering inversion in the observed run —
    // 'write pointer advanced' before 'payload written' — that was an
    // artifact of this mapping rather than anything the title did.
    if (self.gpu_ring_nonzero_dwords != 0) ledger.observe(.ring_payload_written, at);
    if (self.gpu_ring_publication.advances != 0) ledger.observe(.write_pointer_advanced, at);
}

pub fn logUnknownInventory(self: anytype) void {
    const ledger = &self.unknown_inventory;
    const totals = ledger.summary();
    if (totals.total == 0) return;
    if (totals.total == self.unknown_inventory_last_total) return;
    self.unknown_inventory_last_total = totals.total;

    machoCapturePrint(
        "macho-processor: UNKNOWN INVENTORY: observations={d} distinct={d} unretained={d} blocking(distinct/observations)={d}/{d} settled_blockers={d} step={d}; {s}\n",
        .{
            totals.total,
            totals.distinct,
            totals.unretained,
            totals.blocking_distinct,
            totals.blocking_total,
            ledger.settledBlockers(unknown_inventory_mod.settled_blocker_threshold),
            self.executed_steps,
            totals.verdict(),
        },
    );
    var top: [8]unknown_inventory_mod.Entry = undefined;
    const written = ledger.ranked(&top);
    for (top[0..written]) |entry| {
        machoCapturePrint(
            "  unknown {s: <20} value=0x{x} ({d}) blocking={s} count={d} first_step={d} last_step={d} note={s}; {s}\n",
            .{
                entry.domain.label(),
                entry.value,
                entry.value,
                if (entry.blocking) "YES" else "no",
                entry.count,
                entry.first_step,
                entry.last_step,
                if (entry.note_len != 0) entry.noteSlice() else "<none>",
                entry.domain.remedy(),
            },
        );
    }
}

pub fn logGuestKernelStatus(self: anytype) void {
    const ledger = &self.guest_status;
    const totals = ledger.summary();
    // Print even with nothing placed, once lines have been offered. A
    // silent report cannot distinguish a parser that declined every line
    // from a route that delivered none, and that ambiguity cost a whole
    // debugging round on 2026-09-05.
    if (ledger.lines_seen == 0) return;
    if (totals.total == self.guest_status_last_total and totals.total != 0) return;
    self.guest_status_last_total = totals.total;

    machoCapturePrint(
        "macho-processor: GUEST KERNEL STATUS: lines_seen={d} conversions={d} distinct={d} unretained={d} defects={d} classes(success/answered/named/unexplained)={d}/{d}/{d}/{d} step={d}; {s}\n",
        .{
            ledger.lines_seen,
            totals.total,
            totals.distinct,
            totals.unretained,
            totals.defects(),
            totals.by_class[@intFromEnum(guest_status_ledger.Class.success)],
            totals.by_class[@intFromEnum(guest_status_ledger.Class.answered_negative)],
            totals.by_class[@intFromEnum(guest_status_ledger.Class.named_failure)],
            totals.by_class[@intFromEnum(guest_status_ledger.Class.unexplained_failure)],
            self.executed_steps,
            totals.verdict(),
        },
    );
    for (ledger.retained()) |entry| {
        machoCapturePrint(
            "  guest-status 0x{X:0>8} dos={d} class={s: <20} count={d} first_step={d} last_step={d} operation={s}; {s}\n",
            .{
                entry.status,
                entry.dos_error,
                entry.class.label(),
                entry.count,
                entry.first_step,
                entry.last_step,
                if (entry.context_len != 0) entry.contextSlice() else "<none>",
                entry.class.describe(),
            },
        );
    }
}

pub fn logGuestWaitLiveness(self: anytype) void {
    const ledger = &self.guest_wait_liveness;
    machoCapturePrint(
        "macho-processor: GUEST WAIT LIVENESS: waits={d} signalled={d} timed_out={d} bounded_poll_timeouts={d} timing_samples={d} blocked_released={d} ready_on_entry={d} ready={d}% unknown_timing={d} aggregate={s} consumption_proven={s} objects={d} open_entries={d} entry_completed={d} entry_dropped={d} unattributed={d} untracked={d} step={d}; {s}\n",
        .{
            ledger.total_waits,
            ledger.total_signalled,
            ledger.total_timed_out,
            ledger.total_bounded_poll_timeouts,
            ledger.aggregateTimingSamples(),
            ledger.total_blocked_signalled,
            ledger.total_ready_on_entry,
            ledger.aggregateReadyPercent(),
            ledger.total_unknown_timing,
            ledger.aggregateVerdict().label(),
            if (ledger.provesSignalConsumption()) "YES" else "NO",
            ledger.count,
            ledger.open_wait_count,
            ledger.wait_entries_completed,
            ledger.wait_entries_dropped,
            ledger.unattributed_waits,
            ledger.untracked_waits,
            self.executed_steps,
            ledger.verdict(),
        },
    );
    for (ledger.objects[0..ledger.count]) |object| {
        machoCapturePrint(
            "  wait object handle=0x{x:0>8} mode={s} mode_conflicts={d} waits={d} signalled={d} timed_out={d} bounded_poll_timeouts={d} timeout_class={s} timeout_ms={d} timing_samples={d} blocked_released={d} ready_on_entry={d} ready={d}% unknown_timing={d} sets={d} sets_already_signalled={d} consumption_proven={s} verdict={s}\n",
            .{
                object.handle,
                object.event_mode.label(),
                object.event_mode_conflicts,
                object.waits,
                object.signalled,
                object.timed_out,
                object.bounded_poll_timeouts,
                object.timeout_class.label(),
                object.timeout_ms,
                object.timingSamples(),
                object.blocked_signalled,
                object.ready_on_entry,
                object.readyRatioPercent(),
                object.unknown_timing,
                object.sets,
                object.sets_already_signalled,
                if (object.provesSignalConsumption()) "YES" else "NO",
                object.verdict().label(),
            },
        );
    }
    for (ledger.open_waits[0..ledger.open_wait_count]) |entry| {
        machoCapturePrint(
            "  open wait class={s} handle=0x{x:0>8} guest_obj=0x{x:0>8} type={d} tid={d} main={s} bootstrap={s} wait_mode={d} wait_reason={d} alertable={d} timeout_ms={d} pc=0x{x} pc_domain={s} pc_quality={s} lr=0x{x} handle_valid={s} age_steps={d}; completion was not observed\n",
            .{
                entry.classLabel(),
                entry.handle,
                entry.guest_object,
                entry.object_type,
                entry.thread_id,
                if (entry.main_thread) "YES" else "NO",
                if (entry.bootstrap_thread) "YES" else "NO",
                entry.wait_mode,
                entry.wait_reason,
                @as(u32, if (entry.alertable) 1 else 0),
                entry.timeout_ms,
                entry.pc,
                entry.pc_domain.label(),
                entry.pc_quality.label(),
                entry.lr,
                if (entry.handle_valid) "YES" else "NO",
                self.executed_steps -| entry.entered_step,
            },
        );
    }
    if (ledger.worst()) |object| machoCapturePrint(
        "macho-processor: GUEST WAIT LIVENESS: worst object handle=0x{x:0>8} verdict={s} — {s}\n",
        .{ object.handle, object.verdict().label(), object.verdict().meaning() },
    );
}

pub fn logPreinitialization(self: anytype) void {
    self.refreshPreinitialization();
    const ledger = &self.gpu_preinitialization;
    const gap = ledger.firstGap();
    const collapsible = gap == null and ledger.inversion_count == 0 and ledger.inversions_dropped == 0;
    // Once the immutable 13/13 startup contract has been printed, later
    // checkpoints add no information. Suppress the summary as well as the
    // rows; otherwise a completed startup remains one of the loudest lines
    // in a run whose actual frontier is render-target state.
    if (collapsible and self.gpu_preinitialization_collapsed != 0) {
        self.gpu_preinitialization_collapsed +|= 1;
        return;
    }
    if (!collapsible) self.gpu_preinitialization_collapsed = 0;
    machoCapturePrint(
        "macho-processor: GPU PRE-INITIALIZATION: established={d}/{d} first_gap={s} owner={s} inversions={d} (dropped={d}) refused_supplies={d} step={d}; {s}\n",
        .{
            ledger.establishedCount(),
            gpu.preinitialization.element_count,
            if (gap) |element| element.label() else "<none>",
            if (gap) |element| element.owner().label() else "-",
            ledger.inversion_count,
            ledger.inversions_dropped,
            ledger.refused_supplies,
            self.executed_steps,
            ledger.verdict(),
        },
    );
    // A complete contract has nothing left to say element by element.
    // Reprinting thirteen established lines on every checkpoint buries the
    // reports that still have a gap, and a reader scanning for the frontier
    // has to skip them every time. The summary above already carries the
    // count, the ordering check and the refusal count, so the detail is
    // emitted only while it can still name something outstanding.
    //
    // Deliberately keyed on inversions as well as completeness: an
    // out-of-order establishment is a finding even when every element is
    // present, and collapsing it away would hide the one class of defect
    // this ledger exists to catch.
    if (collapsible) {
        self.gpu_preinitialization_collapsed = 1;
        machoCapturePrint(
            "  GPU PRE-INITIALIZATION: complete and in order, so the summary and per-element detail are collapsed from here on. They return automatically if an element is ever lost or an inversion appears\n",
            .{},
        );
        return;
    }
    inline for (@typeInfo(gpu.PreinitElement).@"enum".fields) |field| {
        const element: gpu.PreinitElement = @enumFromInt(field.value);
        const entry = ledger.entries[field.value];
        machoCapturePrint(
            "  preinit {s: <12} {s: <12} {s: <44} step={d} observations={d}{s}{s}\n",
            .{
                element.owner().label(),
                ledger.state(element).label(),
                element.label(),
                entry.step,
                entry.observations,
                if (entry.state.present()) "" else " — ",
                if (entry.state.present()) "" else element.consequence(),
            },
        );
    }
    var index: u32 = 0;
    while (index < ledger.inversion_count) : (index += 1) {
        const inversion = ledger.inversions[index];
        machoCapturePrint(
            "macho-processor: GPU PRE-INITIALIZATION: ORDERING INVERSION #{d}: '{s}' became true at step {d} while '{s}' was still absent. Whatever the title read at that moment it read too early, and nothing re-reads it — {s}\n",
            .{
                index + 1,
                inversion.element.label(),
                inversion.step,
                inversion.prerequisite.label(),
                inversion.prerequisite.consequence(),
            },
        );
    }
    var pending: [gpu.preinitialization.element_count]gpu.PreinitElement = undefined;
    for (ledger.outstandingPlatformWork(&pending)) |element| {
        machoCapturePrint(
            "macho-processor: GPU PRE-INITIALIZATION: platform work outstanding: {s} — {s}\n",
            .{ element.label(), element.consequence() },
        );
    }
}
