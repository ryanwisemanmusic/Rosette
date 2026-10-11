// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const builtin = __ProcessInternals._builtin;
const contract = __ProcessInternals._contract;
const deadlock_predictor = __ProcessInternals._deadlock_predictor;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const gpu = __ProcessInternals._gpu;
const host_contract_coverage = __ProcessInternals._host_contract_coverage;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const notifier_liveness = __ProcessInternals._notifier_liveness;
const preflight_lib = __ProcessInternals._preflight_lib;
const primitive = __ProcessInternals._primitive;
const scheduler = __ProcessInternals._scheduler;
const stall_release = __ProcessInternals._stall_release;
const std = __ProcessInternals._std;
const sync_object_identity = __ProcessInternals._sync_object_identity;
const wait_audit = __ProcessInternals._wait_audit;
const xenia_gpu_causal_trace = __ProcessInternals._xenia_gpu_causal_trace;
const xenia_gpu_handoff = __ProcessInternals._xenia_gpu_handoff;
const xenia_memory_views = __ProcessInternals._xenia_memory_views;
const xenia_pm4_walk = __ProcessInternals._xenia_pm4_walk;
const guestMemory = __ProcessInternals._guestMemory;
const guestMemoryConst = __ProcessInternals._guestMemoryConst;
const init = MachOState.init;
const logNewPm4Fault = MachOState.logNewPm4Fault;
const logSubmissionProvenance = MachOState.logSubmissionProvenance;
const noteGpuInterruptDispatch = MachOState.noteGpuInterruptDispatch;
const observeGpuEarlyBoundary = MachOState.observeGpuEarlyBoundary;
const offerGuestFrontBuffer = MachOState.offerGuestFrontBuffer;
const run = MachOState.run;
const scheduleSignalCallback = MachOState.scheduleSignalCallback;
const step = MachOState.step;
const titleInterruptCallbackRegistrationObserved = MachOState.titleInterruptCallbackRegistrationObserved;
const titleInterruptCallbackRouteProven = MachOState.titleInterruptCallbackRouteProven;

pub fn logRingContents(self: anytype) void {
    self.gpu_ring_inspection_attempted = true;
    self.gpu_ring_last_inspection_step = self.executed_steps;
    if (self.gpu_ring_watch_base == 0 or self.gpu_ring_watch_size == 0) {
        self.recordRingSurveyStarvation(.input_unavailable, .geometry_unknown);
        machoCapturePrint(
            "macho-processor: RING CONTENTS: the ring's base and size have not been observed yet, so there is nothing to read. This is upstream of every packet question: VdInitializeRingBuffer has not run, or its arguments were not seen\n",
            .{},
        );
        return;
    }
    self.gpu_ring_last_inspected_base = self.gpu_ring_watch_base;
    self.gpu_ring_last_inspected_size = self.gpu_ring_watch_size;
    const ring_dwords: u32 = @intCast(@min(self.gpu_ring_watch_size / 4, std.math.maxInt(u32)));
    const virtual_alias: u32 = if (self.gpu_ring_watch_base >= 0x1000)
        @intCast(0xE000_0000 + self.gpu_ring_watch_base - 0x1000)
    else
        0;
    const unbiased = if (virtual_alias != 0)
        self.xenia_memory_views.primaryUnbiasedHostAddress(virtual_alias) orelse 0
    else
        0;

    var survey = gpu.ring_view.Survey{};
    survey.record(gpu.ring_view.examine(
        .physical,
        self.gpu_ring_watch_host_physical,
        self.guestMemoryConst(self.gpu_ring_watch_host_physical, self.gpu_ring_watch_size),
        ring_dwords,
    ));
    survey.record(gpu.ring_view.examine(
        .virtual_biased,
        self.gpu_ring_watch_host_virtual,
        self.guestMemoryConst(self.gpu_ring_watch_host_virtual, self.gpu_ring_watch_size),
        ring_dwords,
    ));
    survey.record(gpu.ring_view.examine(
        .virtual_unbiased,
        unbiased,
        self.guestMemoryConst(unbiased, self.gpu_ring_watch_size),
        ring_dwords,
    ));

    const publication = &self.gpu_ring_publication;
    const published = publication.advances != 0;
    if (publication.geometry != null) {
        self.gpu_vd_swap_contract.observeRingGeometry(self.executed_steps, .memory_mapping);
    }
    self.gpu_ring_scan_reports +|= 1;
    machoCapturePrint(
        "macho-processor: RING CONTENTS: base=0x{x} dwords={d} size=0x{x} projections(readable/written/candidates/payload_readable)={d}/{d}/{d}/{d} aliases_disagree={s}; {s}\n",
        .{
            self.gpu_ring_watch_base,
            ring_dwords,
            self.gpu_ring_watch_size,
            survey.readableCount(),
            survey.writtenCount(),
            survey.swapCandidateCount(),
            survey.readableSwapCandidateCount(),
            if (survey.aliasesDisagree()) "YES" else "NO",
            survey.verdict(published),
        },
    );
    for (survey.readings) |reading| {
        machoCapturePrint(
            "  projection {s: <16} host=0x{x:0>9} readable={s: <3} nonzero_dwords={d: <6} packets={d: <5} draws={d: <4} stream_validated={s: <3} swap_candidates={d} payload_readable={d} malformed={d} truncated={d} swap={s}; {s}\n",
            .{
                reading.projection.label(),
                reading.address,
                if (reading.readable) "YES" else "NO",
                reading.nonzero_dwords,
                reading.packets,
                reading.draws,
                if (reading.stream_validated) "YES" else "NO",
                reading.swap_candidates,
                reading.swap_payload_readable,
                reading.swap_malformed_candidates,
                reading.swap_truncated_candidates,
                if (reading.swap != null) "YES" else "NO",
                reading.projection.meaning(),
            },
        );
    }

    // The span the pointers describe, read out of whichever projection
    // actually holds data. The pointers are frequently zero here because
    // the emulator reports them through a path this process does not see;
    // an empty span is therefore not evidence, and the whole-ring walk
    // above is what the verdict is built on.
    const geometry = publication.geometry orelse blk: {
        for ([_]gpu.VdSwapStage{ .ring_geometry_observed, .ring_projection_readable }) |stage| {
            self.gpu_vd_swap_contract.recordStarvation(stage, .ring_geometry_capture, .input_unavailable, .geometry_unknown, 0, self.executed_steps);
        }
        break :blk gpu.RingGeometry{};
    };
    const span: u32 = if (geometry.write_pointer >= geometry.read_pointer)
        geometry.write_pointer - geometry.read_pointer
    else
        ring_dwords - (geometry.read_pointer - geometry.write_pointer);
    // The stages the outstanding-span walk can supply.  It is recorded
    // against every one of them on every heartbeat, including the
    // heartbeats where it reads nothing: a span of zero is the normal
    // state of a drained ring, and sixteen consecutive empty walks are not
    // sixteen pieces of evidence that the producer wrote no swap.
    const span_stages = [_]gpu.VdSwapStage{
        .ring_projection_readable,
        .pm4_stream_observed,
        .pm4_stream_validated,
        .xe_swap_candidate_seen,
        .xe_swap_packet_readable,
        .xe_swap_packet_decoded,
        .fetch_constant_decoded,
    };
    if (survey.best()) |chosen| {
        if (self.guestMemoryConst(chosen.address, self.gpu_ring_watch_size)) |bytes| {
            if (chosen.readable) {
                self.observeGpuEarlyBoundary(.ring_payload_readable, .ring, chosen.nonzero_dwords);
            }
            const summary = gpu.ring_scan.scan(bytes, geometry.read_pointer, span, ring_dwords);
            if (summary.dwords_examined == 0) {
                for (span_stages) |stage| {
                    self.gpu_vd_swap_contract.recordStarvation(stage, .outstanding_span_scan, .input_empty, .input_drained, 0, self.executed_steps);
                }
            } else {
                self.gpu_vd_swap_contract.observeProbe(.ring_projection_readable, .outstanding_span_scan, chosen.readable, summary.dwords_examined, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.pm4_stream_observed, .outstanding_span_scan, summary.packets != 0, summary.dwords_examined, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.pm4_stream_validated, .outstanding_span_scan, !summary.truncated and !summary.desynchronised and summary.malformed_packets == 0, summary.dwords_scanned, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.xe_swap_candidate_seen, .outstanding_span_scan, summary.swap_candidates != 0, summary.dwords_examined, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.xe_swap_packet_readable, .outstanding_span_scan, summary.swap_payload_readable != 0, summary.swap_candidates, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.xe_swap_packet_decoded, .outstanding_span_scan, summary.swap != null, summary.swap_candidates, self.executed_steps);
                self.gpu_vd_swap_contract.observeProbe(.fetch_constant_decoded, .outstanding_span_scan, summary.fetch != null, summary.dwords_examined, self.executed_steps);
            }
            self.gpu_vd_swap_contract.observePacket(.{
                .projection_readable = chosen.readable,
                .stream_observed = summary.dwords_examined != 0 and summary.zero_dwords < summary.dwords_examined,
                .stream_validated = summary.dwords_examined != 0 and summary.zero_dwords < summary.dwords_examined and
                    !summary.truncated and !summary.desynchronised and summary.malformed_packets == 0,
                .candidate_seen = summary.swap_candidates != 0,
                .readable = summary.swap_payload_readable != 0,
                .decoded = summary.swap != null,
                .swap = summary.swap,
                .fetch = summary.fetch,
                .fetch_decoded = summary.fetch != null,
                .root_packets = summary.packets,
                .draw_packets = summary.draw_packets,
                .swap_packets = summary.swap_packets,
                .malformed_packets = summary.malformed_packets,
                .truncated = summary.truncated,
                .desynchronised = summary.desynchronised,
                .zero_dwords = summary.zero_dwords,
                .dwords_examined = summary.dwords_examined,
                .dwords_scanned = summary.dwords_scanned,
                .span_dwords = summary.span_dwords,
                .packet_offset = summary.swap_offset,
            }, self.executed_steps, .ring_memory_scan);
            self.xenia_gpu_causal_trace.observeRingPayload(
                summary.packets,
                summary.draw_packets,
                summary.swap_packets,
                self.executed_steps,
                self.gpu_ring_injection.injections == 0 and self.gpu_ring_publication.advances != 0,
            );
            machoCapturePrint(
                "  outstanding span: projection={s} read={d} write={d} span={d} examined={d} walked={d} packets={d} draws={d} swaps={d} candidates={d} payload_readable={d} decoded={s} fetch_decoded={s} truncated={s} desync={s}; {s}\n",
                .{
                    chosen.projection.label(),                   geometry.read_pointer,
                    geometry.write_pointer,                      span,
                    summary.dwords_examined,                     summary.dwords_scanned,
                    summary.packets,                             summary.draw_packets,
                    summary.swap_packets,                        summary.swap_candidates,
                    summary.swap_payload_readable,               if (summary.swap != null) "YES" else "NO",
                    if (summary.fetch != null) "YES" else "NO",  if (summary.truncated) "YES" else "NO",
                    if (summary.desynchronised) "YES" else "NO", summary.verdict(),
                },
            );

            // The ring scanner is deliberately read-only.  Once a new
            // publication is observed, hand the same bounded, endian-
            // decoded span to the stateful Xenos command processor so
            // register state, draw state, completion events, and swap
            // descriptions have a single owner.  Do not replay a drained
            // ring when the producer has not advanced its publication.
            if (span != 0 and self.gpu_xenos_last_ring_epoch != publication.advances) {
                self.gpu_xenos_last_ring_epoch = publication.advances;
                self.gpu_xenos_runtime.attachMemory(
                    self,
                    xenosMemoryRead,
                    self,
                    xenosMemoryWrite,
                );
                // Decode the exact bytes independently before the stateful
                // executor is allowed to publish guest-visible effects.
                // A completion packet may write memory; taking the walk
                // afterward would no longer prove both decoders saw the
                // same content.
                var authority_walker = xenia_pm4_walk.Walker.init(self, xenosMemoryRead);
                authority_walker.walkRoot(bytes, geometry.read_pointer, span, ring_dwords);
                const authority_walk = authority_walker.summary();
                const authority_batch_id = self.pm4BatchIdentity(
                    bytes,
                    geometry.read_pointer,
                    span,
                    ring_dwords,
                    authority_walk.content_fingerprint,
                );
                const authentic_execution = self.gpu_ring_injection.injections == 0 and
                    self.gpu_ring_publication.published();
                const authority_source: gpu.pm4_authority.SourceClass = if (authentic_execution)
                    .guest_authentic
                else if (self.gpu_ring_injection.injections != 0)
                    .synthetic
                else
                    .host_forwarded;
                self.recordPm4AuthorityWalk(authority_batch_id, authority_walk, authority_source);
                if (self.gpu_xenos_runtime.executeRingBytes(bytes, geometry.read_pointer, span, ring_dwords)) |execution| {
                    self.recordPm4AuthorityExecution(
                        authority_batch_id,
                        execution,
                        authority_source,
                    );
                    // `draws` includes Xenia's legitimate no-effect
                    // IssueDraw entries. Only the runtime's explicit
                    // target-backed classification can participate in the
                    // strict render-target ordering contract.
                    if (execution.renderable_draw_observations != 0 and
                        self.gpu_renderable_draw_first_step == 0)
                    {
                        self.gpu_renderable_draw_first_step = self.executed_steps;
                        self.gpu_renderable_draw_first_thread = self.active_guest_thread;
                    }
                    if ((execution.renderable_draw_observations != 0 or
                        self.gpu_xenos_runtime.color_resolve_observations != 0) and
                        self.gpu_guest_output_first_step == 0)
                    {
                        self.gpu_guest_output_first_step = self.executed_steps;
                        self.gpu_guest_output_first_thread = self.active_guest_thread;
                    }
                    self.observeGpuEarlyPacketExecution(
                        execution,
                        authentic_execution,
                    );
                    const indirect = self.xenia_gpu_causal_trace.observePm4SpanWithIndirects(
                        bytes,
                        geometry.read_pointer,
                        span,
                        ring_dwords,
                        @max(self.gpu_ring_publication.advances, 1),
                        self.executed_steps,
                        true,
                        self.gpu_ring_injection.injections == 0 and self.gpu_ring_publication.advances != 0,
                        self,
                        xenosMemoryRead,
                    );
                    const indirect_packets: u64 = @as(u64, indirect.root_packets) + @as(u64, indirect.nested_packets);
                    const indirect_draws: u64 = indirect.draw_packets;
                    const indirect_swaps: u64 = indirect.swap_packets;
                    const executed_packets = execution.packets_after - execution.packets_before;
                    const indirects_resolved = indirect.unreadable_references == 0 and
                        indirect.invalid_references == 0 and
                        indirect.cycle_references == 0 and
                        indirect.depth_limited_references == 0 and
                        indirect.truncated_references == 0 and
                        indirect.budget_limited_references == 0;
                    const stream_observed = execution.dwords != 0 or executed_packets != 0;
                    const stream_validated = stream_observed and !execution.truncated;
                    const runtime_fetch = self.gpu_xenos_runtime.frontBufferFetch();
                    const execution_runtime_swap = self.gpu_xenos_runtime.last_swap;
                    self.gpu_vd_swap_contract.observePacket(.{
                        .projection_readable = true,
                        .stream_observed = stream_observed,
                        .stream_validated = stream_validated,
                        .indirects_resolved = indirects_resolved,
                        .candidate_seen = execution.swaps != 0 or execution_runtime_swap != null,
                        .readable = execution_runtime_swap != null,
                        .decoded = execution_runtime_swap != null,
                        .swap = execution_runtime_swap,
                        .fetch = runtime_fetch,
                        .fetch_decoded = runtime_fetch != null,
                        .root_packets = executed_packets,
                        .nested_packets = indirect.nested_packets,
                        .indirect_packets = indirect.indirect_packets,
                        .draw_packets = execution.draws,
                        .swap_packets = execution.swaps,
                        .truncated = execution.truncated,
                        .unknown_opcodes = execution.unknown_opcodes,
                        .unreadable_references = indirect.unreadable_references,
                        .authentic_consumption = execution_runtime_swap != null and
                            self.gpu_ring_injection.injections == 0 and
                            self.gpu_ring_publication.published(),
                    }, self.executed_steps, .stateful_pm4_executor);
                    const consumed_packets = if (executed_packets > indirect_packets) executed_packets else indirect_packets;
                    const consumed_draws = if (execution.draws > indirect_draws) execution.draws else indirect_draws;
                    const consumed_swaps = if (execution.swaps > indirect_swaps) execution.swaps else indirect_swaps;
                    if (consumed_draws != 0) {
                        self.gpu_ring_draws_seen = true;
                        const draw_count: u32 = @intCast(@min(consumed_draws, @as(u64, std.math.maxInt(u32))));
                        if (draw_count > self.gpu_ring_draws_last_count) self.gpu_ring_draws_last_count = draw_count;
                    }
                    self.gpu_ring_publication.observeConsumedBatch(
                        span,
                        consumed_packets,
                        consumed_draws,
                        consumed_swaps,
                        self.executed_steps,
                    );
                    self.xenia_gpu_causal_trace.observeConsumedBatch(
                        @intCast(@min(consumed_packets, @as(u64, std.math.maxInt(u32)))),
                        @intCast(@min(consumed_draws, @as(u64, std.math.maxInt(u32)))),
                        @intCast(@min(consumed_swaps, @as(u64, std.math.maxInt(u32)))),
                        self.executed_steps,
                        self.gpu_ring_injection.injections == 0 and self.gpu_ring_publication.advances != 0,
                    );
                    machoCapturePrint(
                        "macho-processor: XENOS PM4 execution: batches={d} dwords={d} packets={d} draws={d} renderable_draws={d} events={d} swaps={d} unknown={d} truncated={s}; observed_packets={d} observed_draws={d} observed_swaps={d} indirect_buffers={d} indirect_read={d}/{d} indirect_status={s} indirect_address=0x{x:0>8} indirect_missing=0x{x:0>8}; state_draws={d} state_renderable_draws={d} state_swaps={d}\n",
                        .{
                            self.gpu_xenos_runtime.batches,
                            execution.dwords,
                            execution.packets_after - execution.packets_before,
                            execution.draws,
                            execution.renderable_draw_observations,
                            execution.events,
                            execution.swaps,
                            execution.unknown_opcodes,
                            if (execution.truncated) "YES" else "NO",
                            consumed_packets,
                            consumed_draws,
                            consumed_swaps,
                            execution.indirect_buffers,
                            execution.indirect_dwords_read,
                            execution.indirect_dwords_requested,
                            execution.indirect_last_status.label(),
                            execution.indirect_last_address,
                            execution.indirect_last_missing_address orelse 0,
                            self.gpu_xenos_runtime.draw_count,
                            self.gpu_xenos_runtime.renderable_draw_observations,
                            self.gpu_xenos_runtime.swap_count,
                        },
                    );
                    if (execution.draw_resource_draws != 0) {
                        const mapping = execution.last_draw_resources;
                        machoCapturePrint(
                            "macho-processor: XENOS DRAW RESOURCE MAPPING: draws={d} probes={d} complete={d} unmapped_draws={d} unproven_draws={d} probe_failures(unmapped/unproven)={d}/{d}; last(target_ready/index/vertex/texture)={s}/{s}/{s}/{s} vertex_bindings={d} texture_bindings={d} first_unmapped=0x{x} first_unproven=0x{x}; command memory mapping is independent of these draw-resource probes\n",
                            .{
                                execution.draw_resource_draws,
                                execution.draw_resource_probes,
                                execution.draws_with_complete_resources,
                                execution.draws_with_unmapped_resources,
                                execution.draws_with_unproven_resources,
                                execution.draw_resources_unmapped,
                                execution.draw_resources_unproven,
                                if (mapping) |value| if (value.target_ready) "YES" else "NO" else "unknown",
                                if (mapping) |value| value.index.label() else "unknown",
                                if (mapping) |value| value.vertex.label() else "unknown",
                                if (mapping) |value| value.texture.label() else "unknown",
                                if (mapping) |value| value.vertex_bindings else 0,
                                if (mapping) |value| value.texture_bindings else 0,
                                if (mapping) |value| value.first_unmapped_address orelse 0 else 0,
                                if (mapping) |value| value.first_unproven_address orelse 0 else 0,
                            },
                        );
                    }
                    if (execution.rectangle_draws != 0) {
                        const route = if (execution.rectangle_backend) |backend| backend.label() else "none";
                        const rejection = if (execution.rectangle_rejection) |reason| reason.label() else "none";
                        const plan = execution.rectangle_plan;
                        machoCapturePrint(
                            "macho-processor: XENOS PM4 rectangle backend: observed={d} lowered={d} empty={d} rejected={d} host_indices={d} trailing_vertices={d} route={s} rejection={s} plan(guest_vertices/rectangles/topology/vertex/geometry/index_format/index_count/restart/builtin)={d}/{d}/{s}/{s}/{s}/{s}/{d}/{s}/{s}; Rosetta generated the Xenia-compatible rectangle plan, while the loaded-image IssueDraw repair leaves Xenia's shader translator and vkCmdDrawIndexed submission owner intact\n",
                            .{
                                execution.rectangle_draws,
                                execution.rectangle_draws_lowered,
                                execution.rectangle_draws_empty,
                                execution.rectangle_draws_rejected,
                                execution.rectangle_host_indices,
                                execution.rectangle_trailing_vertices,
                                route,
                                rejection,
                                if (plan) |value| value.guest_vertex_count else 0,
                                if (plan) |value| value.rectangle_count else 0,
                                if (plan) |value| @tagName(value.host_topology) else "none",
                                if (plan) |value| value.host_vertex_shader.label() else "none",
                                if (plan) |value| value.host_geometry_shader.label() else "none",
                                if (plan) |value| @tagName(value.host_index_format) else "none",
                                if (plan) |value| value.host_index_count else 0,
                                if (plan) |value| if (value.host_primitive_restart) "YES" else "NO" else "NO",
                                if (plan) |value| if (value.uses_builtin_index_buffer) "YES" else "NO" else "NO",
                            },
                        );
                    }
                    if (execution.swaps != 0) {
                        if (self.gpu_xenos_runtime.last_swap) |runtime_swap| {
                            if (runtime_swap.plausible()) {
                                self.gpu_frontbuffer = runtime_swap;
                                self.gpu_vd_swap_contract.observeFrontBuffer(
                                    runtime_swap,
                                    .stateful_pm4_executor,
                                    self.executed_steps,
                                );
                                self.offerGuestFrontBuffer(runtime_swap, self.gpu_xenos_runtime.frontBufferFetch(), false);
                                machoCapturePrint(
                                    "macho-processor: XENOS PM4 present handoff: frontbuffer=0x{x:0>8} extent={d}x{d} fetch={s}; stateful command processing supplied the presenter even when the generic ring scanner did not decode the swap\n",
                                    .{
                                        runtime_swap.frontbuffer_physical_address,
                                        runtime_swap.width,
                                        runtime_swap.height,
                                        if (self.gpu_xenos_runtime.frontBufferFetch() != null) "observed" else "absent (defaults apply)",
                                    },
                                );
                            }
                        }
                    }
                } else |err| {
                    machoCapturePrint(
                        "macho-processor: XENOS PM4 execution refused: error={s} read={d} write={d} span={d} ring_dwords={d}\n",
                        .{ @errorName(err), geometry.read_pointer, geometry.write_pointer, span, ring_dwords },
                    );
                    self.logNewPm4Fault();
                }
                if (self.gpu_interrupt_callback != 0) {
                    const delivered = self.gpu_xenos_runtime.drainInterrupts(deliverGpuInterrupt, self, 32);
                    if (delivered != 0) {
                        machoCapturePrint(
                            "macho-processor: XENOS GPU interrupts queued: delivered={d} callback=0x{x} arg=0x{x}\n",
                            .{ delivered, self.gpu_interrupt_callback, self.gpu_interrupt_callback_arg },
                        );
                    }
                }
            }
        } else {
            // The projection the survey chose cannot be read back here.
            // That is a memory-view question, and saying so is what keeps
            // it from reading as an absence in the producer.
            self.recordRingSurveyStarvation(.input_unavailable, .memory_unreadable);
        }
    } else {
        // No projection of the ring could be chosen at all, so the
        // survey and every walk fed from it looked at nothing this
        // round. Recorded rather than skipped: an unrecorded round
        // leaves these probes reading `not attempted` forever, which
        // accuses the transport of a silence that is Rosette's.
        self.recordRingSurveyStarvation(.input_unavailable, .geometry_unknown);
    }

    if (survey.best()) |chosen| {
        if (chosen.draws != 0) self.gpu_ring_draws_seen = true;
        if (chosen.draws > self.gpu_ring_draws_last_count) self.gpu_ring_draws_last_count = chosen.draws;
        self.gpu_ring_nonzero_dwords = chosen.nonzero_dwords;
        // The whole-ring survey is the strongest negative evidence the
        // subsystem has: it reads every dword of a readable projection,
        // drained or outstanding.  When it finds no XE_SWAP the title
        // really did not write one, and that is a finding against the
        // producer rather than a hole in the observer.  When the projection
        // holds nothing at all the reverse is true, so the two are recorded
        // as different outcomes.
        const survey_stages = [_]gpu.VdSwapStage{
            .xe_swap_candidate_seen,
            .xe_swap_packet_readable,
            .xe_swap_packet_decoded,
        };
        if (!chosen.readable) {
            for (survey_stages) |stage| {
                self.gpu_vd_swap_contract.recordStarvation(stage, .ring_projection_survey, .input_unavailable, .memory_unreadable, 0, self.executed_steps);
            }
            self.gpu_vd_swap_contract.recordStarvation(.ring_projection_readable, .ring_projection_survey, .input_unavailable, .memory_unreadable, 0, self.executed_steps);
            // The scan reads the same projection, so it is starved for the
            // same reason. Recorded here rather than only in the branch
            // below, because a probe that skips a round says "nobody was
            // watching" where it means "I looked and could not read".
            self.gpu_vd_swap_contract.recordStarvation(.frontbuffer_validated, .retained_batch_scan, .input_unavailable, .memory_unreadable, 0, self.executed_steps);
        } else if (chosen.nonzero_dwords == 0) {
            for (survey_stages) |stage| {
                self.gpu_vd_swap_contract.recordStarvation(stage, .ring_projection_survey, .input_empty, .input_drained, 0, self.executed_steps);
            }
            self.gpu_vd_swap_contract.observeProbe(.ring_projection_readable, .ring_projection_survey, true, 0, self.executed_steps);
            self.gpu_vd_swap_contract.recordStarvation(.frontbuffer_validated, .retained_batch_scan, .input_empty, .input_drained, 0, self.executed_steps);
        } else {
            self.gpu_vd_swap_contract.observeProbe(.ring_projection_readable, .ring_projection_survey, true, chosen.nonzero_dwords, self.executed_steps);
            self.gpu_vd_swap_contract.observeProbe(.pm4_stream_observed, .ring_projection_survey, chosen.packets != 0, chosen.nonzero_dwords, self.executed_steps);
            self.gpu_vd_swap_contract.observeProbe(.pm4_stream_validated, .ring_projection_survey, chosen.stream_validated, chosen.packets, self.executed_steps);
            self.gpu_vd_swap_contract.observeProbe(.xe_swap_candidate_seen, .ring_projection_survey, chosen.swap_candidates != 0, chosen.nonzero_dwords, self.executed_steps);
            self.gpu_vd_swap_contract.observeProbe(.xe_swap_packet_readable, .ring_projection_survey, chosen.swap_payload_readable != 0, chosen.swap_candidates, self.executed_steps);
            self.gpu_vd_swap_contract.observeProbe(.xe_swap_packet_decoded, .ring_projection_survey, chosen.swap != null, chosen.swap_candidates, self.executed_steps);
            self.gpu_vd_swap_contract.observeProbe(.frontbuffer_validated, .retained_batch_scan, chosen.swap != null, chosen.nonzero_dwords, self.executed_steps);
        }
        self.gpu_vd_swap_contract.observePacket(.{
            .projection_readable = chosen.readable,
            .stream_observed = chosen.nonzero_dwords != 0 and chosen.packets != 0,
            .stream_validated = chosen.stream_validated,
            .candidate_seen = chosen.swap_candidates != 0,
            .readable = chosen.swap_payload_readable != 0,
            .decoded = chosen.swap != null,
            .swap = chosen.swap,
            .fetch = chosen.fetch,
            .fetch_decoded = chosen.fetch != null,
            .root_packets = chosen.packets,
            .draw_packets = chosen.draws,
            .swap_packets = chosen.swap_candidates,
            .malformed_packets = chosen.swap_malformed_candidates,
            .truncated = chosen.swap_truncated_candidates != 0,
            .packet_offset = chosen.swap_offset,
        }, self.executed_steps, .ring_memory_scan);
        self.logRingPayload(chosen);
    }
    self.logSubmissionProvenance();
    machoCapturePrint(
        "  whole-ring draw search: effective_draws(root_or_nested)={d} ever_seen={s}; the outstanding span is what the pointers describe, and a batch the command processor already drained is still in the ring. Absence here is weak evidence and presence is strong\n",
        .{ self.gpu_ring_draws_last_count, if (self.gpu_ring_draws_seen) "YES" else "NO" },
    );

    // The pointers describe what is outstanding. A swap the command
    // processor already drained is still in the ring, and "was one ever
    // written" is a different and more useful question than "is one
    // waiting" — a yes here with a zero swap counter upstream means the
    // packet was written and not decoded, which is a completely different
    // defect from one that was never written.
    const found: ?gpu.Pm4SwapDescription = if (survey.best()) |chosen| chosen.swap else null;
    if (found) |swap| {
        if (self.gpu_frontbuffer == null) machoCapturePrint(
            "macho-processor: RING CONTENTS: a swap packet is present in ring memory: frontbuffer=0x{x:0>8} extent={d}x{d} plausible={s}. The title did write a present request into the ring at some point in this run, whatever the swap counters say\n",
            .{ swap.frontbuffer_physical_address, swap.width, swap.height, if (swap.plausible()) "YES" else "NO" },
        );
        if (swap.plausible()) {
            self.gpu_frontbuffer = swap;
            self.gpu_vd_swap_contract.observeFrontBuffer(swap, .ring_memory_scan, self.executed_steps);
            self.offerGuestFrontBuffer(swap, if (survey.best()) |chosen| chosen.fetch else null, false);
        }
    } else {
        machoCapturePrint(
            "macho-processor: RING CONTENTS: no XE_SWAP packet exists in any readable projection of the ring, drained or outstanding. The title has never written a present request, so the absence is the producer's and not the command processor's\n",
            .{},
        );
    }
}

pub fn deliverGpuInterrupt(context: *anyopaque, event: gpu.interrupt_controller.Event) void {
    const self: *MachOState = @ptrCast(@alignCast(context));
    self.gpu_interrupt_dispatches +|= 1;
    const is_draw_completion = event.kind == .draw_complete;
    if (is_draw_completion) self.gpu_draw_completion_dispatch_attempts +|= 1;
    const registration_proven = self.titleInterruptCallbackRegistrationObserved();
    const route_proven = self.titleInterruptCallbackRouteProven();
    self.noteGpuInterruptDispatch();
    if (!route_proven) {
        if (is_draw_completion) self.gpu_draw_completion_dispatch_failures +|= 1;
        self.gpu_interrupt_dispatch_failures +|= 1;
        machoCapturePrint(
            "macho-processor: XENOS GPU interrupt dispatch refused: callback=0x{x} slot=0x{x:0>8} slot_owner={s} registration_proven={s} callback_route_proven={s} translated_x86_registrations={d} event={s} id=0x{x} value=0x{x}; a synthetic or host callback cannot enter while the shared slot is not occupied by the ordered title route\n",
            .{
                self.gpu_interrupt_callback,
                self.gpu_interrupt_slot_address,
                if (self.gpu_interrupt_slot_is_guest) "guest:title" else "emulator:host-builtin",
                if (registration_proven) "YES" else "NO",
                if (route_proven) "YES" else "NO",
                self.gpu_interrupt_callback_registrations,
                @tagName(event.kind),
                event.id,
                event.value,
            },
        );
        return;
    }
    // The authentic binding first. Only when there is none does the
    // dispatch scaffold offer an address it resolved from a weaker source,
    // and only when policy admits that source. The two are never merged:
    // `gpu_interrupt_callback` stays the binding so every existing report
    // that reads it keeps meaning what it meant.
    var callback = self.gpu_interrupt_callback;
    var callback_arg = self.gpu_interrupt_callback_arg;
    var substituted = false;
    if (callback == 0) {
        const scaffold = &self.gpu_draw_dispatch;
        if (scaffold.wouldDispatch(1) == .delivered) {
            callback = scaffold.callback.address;
            callback_arg = scaffold.callback.user_data;
            substituted = true;
        }
    }
    if (callback == 0) {
        if (is_draw_completion) self.gpu_draw_completion_dispatch_failures +|= 1;
        self.gpu_draw_dispatch.recordAttempt(
            self.gpu_draw_dispatch.wouldDispatch(1),
            1,
            0,
            self.executed_steps,
        );
        return;
    }
    const source = self.scheduleSignalCallback(
        callback,
        callback_arg,
        event.id,
        event.value,
        "xenia_gpu_interrupt",
    );
    if (source == 0) {
        self.gpu_interrupt_dispatch_failures +|= 1;
        if (is_draw_completion) self.gpu_draw_completion_dispatch_failures +|= 1;
        if (substituted) self.gpu_draw_dispatch.recordAttempt(.failed, 1, 0, self.executed_steps);
        machoCapturePrint(
            "macho-processor: XENOS GPU interrupt callback rejected: callback=0x{x} substituted={s} event={s} id=0x{x} value=0x{x}; guest execution was not fabricated\n",
            .{ callback, if (substituted) "YES" else "NO", @tagName(event.kind), event.id, event.value },
        );
        return;
    }
    if (is_draw_completion) self.gpu_draw_completion_dispatches +|= 1;
    if (substituted) {
        self.gpu_draw_dispatch.recordAttempt(.delivered, 1, 1, self.executed_steps);
        machoCapturePrint(
            "macho-processor: DRAW DISPATCH: delivered a completion to callback=0x{x} provenance={s} event={s} id=0x{x}; Rosette originated this, so it is a substitution and can never close the authentic dispatch stage\n",
            .{
                callback,
                self.gpu_draw_dispatch.callback.provenance.label(),
                @tagName(event.kind),
                event.id,
            },
        );
    } else {
        // The emulator's own binding carried it. This is the authentic path.
        self.gpu_bootstrap.observe(.graphics_interrupt_dispatch, self.executed_steps);
    }
}

pub fn xenosGpuSwap(value: u32, endian: u2) u32 {
    return switch (endian) {
        0 => value,
        1 => ((value << 8) & 0xFF00_FF00) | ((value >> 8) & 0x00FF_00FF),
        2 => @byteSwap(value),
        3 => (value >> 16) | (value << 16),
    };
}

pub fn xenosProjectionHostAddress(
    self: anytype,
    address: u32,
    projection: xenia_memory_views.PhysicalProjection,
) ?u64 {
    const aligned = address & ~@as(u32, 3);
    return self.xenia_memory_views.physicalProjectionHostAddress(aligned, projection);
}

pub fn xenosReadProjection(
    self: anytype,
    address: u32,
    projection: xenia_memory_views.PhysicalProjection,
) ?u32 {
    const host = self.xenosProjectionHostAddress(address, projection) orelse return null;
    const bytes = self.guestMemoryConst(host, 4) orelse return null;
    // Xenia's TranslatePhysical backing stores Xbox words in big-endian
    // memory. This is the direct equivalent of Xenia's
    // load_and_swap<uint32_t> on a little-endian macOS host.
    const raw = std.mem.readInt(u32, bytes[0..4], .big);
    return xenosGpuSwap(raw, @truncate(address));
}

pub fn xenosWriteProjection(
    self: anytype,
    address: u32,
    value: u32,
    endian: u2,
    projection: xenia_memory_views.PhysicalProjection,
) bool {
    const host = self.xenosProjectionHostAddress(address, projection) orelse return false;
    const bytes = self.guestMemory(host, 4) orelse return false;
    std.mem.writeInt(u32, bytes[0..4], xenosGpuSwap(value, endian), .big);
    return true;
}

pub fn noteXenosAliasFallback(self: anytype, address: u32, disagreement: bool) void {
    self.gpu_xenos_memory_alias_fallbacks +|= 1;
    if (disagreement) self.gpu_xenos_memory_alias_disagreements +|= 1;
    self.gpu_xenos_memory_alias_log_count +|= 1;
    const count = self.gpu_xenos_memory_alias_log_count;
    if (count <= 8 or (count % 256) == 0) {
        machoCapturePrint(
            "macho-processor: XENOS MEMORY projection fallback #{d}: physical=UNREADABLE address=0x{x:0>8} aliases_disagree={s}; {s}\n",
            .{
                count,
                address,
                if (disagreement) "YES" else "NO",
                if (disagreement) "read refused (zero-trust)" else "alias value accepted",
            },
        );
    }
}

pub fn xenosMemoryRead(context: *anyopaque, address: u32) ?u32 {
    const self: *MachOState = @ptrCast(@alignCast(context));
    if (self.xenosReadProjection(address, .physical)) |value| return value;
    self.gpu_xenos_memory_physical_misses +|= 1;

    var fallback: ?u32 = null;
    var disagreement = false;
    inline for ([_]xenia_memory_views.PhysicalProjection{ .a_virtual, .c_virtual, .e_virtual }) |projection| {
        if (self.xenosReadProjection(address, projection)) |value| {
            if (fallback) |existing| {
                if (existing != value) disagreement = true;
            } else {
                fallback = value;
            }
        }
    }
    if (disagreement) {
        self.noteXenosAliasFallback(address, true);
        return null;
    }
    if (fallback != null) self.noteXenosAliasFallback(address, false);
    return fallback;
}

pub fn xenosMemoryWrite(context: *anyopaque, address: u32, value: u32, endian: u2) bool {
    const self: *MachOState = @ptrCast(@alignCast(context));
    if (self.xenosWriteProjection(address, value, endian, .physical)) return true;
    self.gpu_xenos_memory_physical_misses +|= 1;

    var wrote_alias = false;
    inline for ([_]xenia_memory_views.PhysicalProjection{ .a_virtual, .c_virtual, .e_virtual }) |projection| {
        if (self.xenosWriteProjection(address, value, endian, projection)) wrote_alias = true;
    }
    if (wrote_alias) self.noteXenosAliasFallback(address, false);
    return wrote_alias;
}

pub fn pm4BatchIdentity(
    self: anytype,
    bytes: []const u8,
    start: u32,
    dwords: u32,
    ring_dwords: u32,
    content_fingerprint: u64,
) u64 {
    var hasher = std.hash.Wyhash.init(0x504d_3441_5544_4954);
    const generation = @max(self.gpu_ring_publication.advances, 1);
    hasher.update(std.mem.asBytes(&generation));
    hasher.update(std.mem.asBytes(&start));
    hasher.update(std.mem.asBytes(&dwords));
    hasher.update(std.mem.asBytes(&ring_dwords));
    // The root can be identical while an INDIRECT_BUFFER target changes.
    // The independent walker fingerprints every readable root and nested
    // dword, so those are different batches rather than two accounts that
    // are accidentally compared as one.
    hasher.update(std.mem.asBytes(&content_fingerprint));
    if (ring_dwords != 0) {
        var index: u32 = 0;
        while (index < dwords) : (index += 1) {
            const ring_index = (@as(u64, start) + index) % ring_dwords;
            const offset = @as(usize, @intCast(ring_index)) * 4;
            if (offset > bytes.len or bytes.len - offset < 4) break;
            hasher.update(bytes[offset .. offset + 4]);
        }
    }
    const value = hasher.final();
    return if (value == 0) 1 else value;
}

pub fn pm4AuthorityAccount(
    execution: gpu.xenos_runtime.Report,
    batch_id: u64,
    source: gpu.pm4_authority.SourceClass,
) gpu.pm4_authority.Account {
    const summary = execution.packet_summary;
    var account = gpu.pm4_authority.Account{
        .domain = .rosette_gpu,
        .source = source,
        .decoder = .stateful_executor,
        .batch_id = batch_id,
        .dwords_examined = summary.root_dwords +| summary.nested_dwords,
        .root_packets = summary.root_packets,
        .nested_packets = summary.nested_packets,
        .indirect_references = summary.classCount(.indirect),
        .register_writes = execution.command_register_writes,
        .draws = summary.classCount(.draw),
        .event_writes = summary.classCount(.event),
        .swaps = summary.classCount(.emulator_extension),
    };
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.truncated)] =
        @intFromBool(execution.truncated) +| execution.indirect_truncated;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.malformed_header)] =
        (execution.packet_errors -| @as(u64, @intFromBool(execution.truncated))) +|
        execution.invalid_packets;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.unknown_opcode)] =
        summary.classCount(.unknown);
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.indirect_unreadable)] =
        execution.indirect_unreadable;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.indirect_depth)] =
        execution.indirect_depth_limited +| execution.indirect_budget_limited;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.register_out_of_range)] =
        execution.command_out_of_range_register_writes;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.register_unclassified)] =
        execution.command_unclassified_register_writes;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.desynchronised)] =
        execution.indirect_invalid +| execution.indirect_cycles;
    return account;
}

pub fn pm4AuthorityWalkAccount(
    summary: xenia_pm4_walk.Summary,
    batch_id: u64,
    source: gpu.pm4_authority.SourceClass,
) gpu.pm4_authority.Account {
    var account = gpu.pm4_authority.Account{
        .domain = .rosette_gpu,
        .source = source,
        .decoder = .structural_walk,
        .batch_id = batch_id,
        .dwords_examined = summary.words_read,
        .root_packets = summary.root_packets,
        .nested_packets = summary.nested_packets,
        .indirect_references = summary.indirect_references,
        .register_writes = summary.command_register_writes,
        .draws = summary.draw_packets,
        .event_writes = summary.packet_class_counts[@intFromEnum(xenia_pm4_walk.PacketClass.event)],
        .swaps = summary.swap_packets,
    };
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.truncated)] =
        @intFromBool(summary.root_truncated) +| summary.truncated_references;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.unknown_opcode)] =
        summary.unknown_packets;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.indirect_unreadable)] =
        summary.unreadable_references;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.indirect_depth)] =
        summary.depth_limited_references +| summary.budget_limited_references +|
        @intFromBool(summary.packet_budget_exhausted);
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.register_out_of_range)] =
        summary.command_out_of_range_register_writes;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.register_unclassified)] =
        summary.command_unclassified_register_writes;
    account.defects[@intFromEnum(gpu.pm4_authority.DefectKind.desynchronised)] =
        summary.invalid_references +| summary.cycle_references;
    return account;
}

pub fn recordPm4AuthorityAccount(
    self: anytype,
    account_value: gpu.pm4_authority.Account,
) void {
    if (account_value.batch_id == 0) return;
    if (self.audit_pm4.batch_id != account_value.batch_id) self.audit_pm4.open(account_value.batch_id);
    // A decoder gets one account per exact batch. A second checkpoint is
    // another observation, not independent corroboration.
    for (self.audit_pm4.retained()) |existing| {
        if (existing.decoder == account_value.decoder) return;
    }
    if (!self.audit_pm4.record(account_value)) return;
    machoCapturePrint(
        "macho-processor: PM4 AUTHORITY ACCOUNT: decoder={s} source={s} batch=0x{x} dwords={d} packets(root/nested)={d}/{d} indirect={d} register_intents={d} draws={d} events={d} swaps={d} defects={d}; authority requires two independently implemented decoders of this exact root-and-indirect content to agree on every semantic count\n",
        .{
            account_value.decoder.label(),
            account_value.source.label(),
            account_value.batch_id,
            account_value.dwords_examined,
            account_value.root_packets,
            account_value.nested_packets,
            account_value.indirect_references,
            account_value.register_writes,
            account_value.draws,
            account_value.event_writes,
            account_value.swaps,
            account_value.totalDefects(),
        },
    );
}

pub fn recordPm4AuthorityWalk(
    self: anytype,
    batch_id: u64,
    summary: xenia_pm4_walk.Summary,
    source: gpu.pm4_authority.SourceClass,
) void {
    self.recordPm4AuthorityAccount(pm4AuthorityWalkAccount(summary, batch_id, source));
}

pub fn recordPm4AuthorityExecution(
    self: anytype,
    batch_id: u64,
    execution: gpu.xenos_runtime.Report,
    source: gpu.pm4_authority.SourceClass,
) void {
    self.recordPm4AuthorityAccount(pm4AuthorityAccount(execution, batch_id, source));
}

pub fn observeGpuEarlyPacketExecution(
    self: anytype,
    execution: gpu.xenos_runtime.Report,
    authentic: bool,
) void {
    const summary = execution.packet_summary;
    if (summary.packets != 0) {
        self.observeGpuEarlyBoundary(.command_processor_entered, .xenos, summary.packets);
    }
    if (summary.root_packets != 0) {
        self.observeGpuEarlyBoundary(.root_pm4_consumed, .pm4, summary.root_packets);
    }
    if (summary.nested_packets != 0) {
        self.observeGpuEarlyBoundary(.nested_pm4_consumed, .pm4, summary.nested_packets);
    }
    if (summary.hasExecuted(.state)) {
        self.observeGpuEarlyBoundary(.pm4_state_programmed, .pm4, summary.executedClassCount(.state));
    }
    if (summary.hasExecuted(.draw)) {
        self.observeGpuEarlyBoundary(.draw_submitted, .xenos, summary.executedClassCount(.draw));
    }
    const target = self.gpu_xenos_runtime.renderTargetEvidence();
    if (target.state_observed) {
        self.observeGpuEarlyBoundary(.render_target_state_observed, .xenos, target.raw_color_info);
    }
    if (self.gpu_xenos_runtime.color_resolve_observations != 0) {
        self.observeGpuEarlyBoundary(
            .render_target_memory_observed,
            .xenos,
            self.gpu_xenos_runtime.color_resolve_observations,
        );
    }
    if (execution.draw_completion_signals != 0) {
        self.observeGpuEarlyBoundary(.draw_completion_signaled, .xenos, execution.draw_completion_signals);
    }
    if (self.gpu_draw_completion_dispatches != 0) {
        self.observeGpuEarlyBoundary(
            .draw_completion_dispatched,
            .scheduler,
            self.gpu_draw_completion_dispatches,
        );
    }
    if (summary.has(.emulator_extension)) {
        self.observeGpuEarlyBoundary(
            .xe_swap_candidate_seen,
            .pm4,
            summary.classCount(.emulator_extension),
        );
    }
    if (execution.swaps != 0 and authentic) {
        self.observeGpuEarlyBoundary(.authentic_xe_swap_consumed, .pm4, execution.swaps);
    }
    if (self.guest_vdswap_packet_encoded) {
        self.observeGpuEarlyBoundary(.guest_swap_encoded, .tracepoint, @intFromBool(self.guest_vdswap_packet_encoded));
    }
    const last_class = if (summary.last) |last| last.class.label() else "none";
    const last_opcode = if (summary.last) |last|
        if (last.opcode) |opcode| @intFromEnum(opcode) else 0
    else
        0;
    machoCapturePrint(
        "macho-processor: XENOS PACKET TRACE: root={d} nested={d} executed={d} executed(root/nested)={d}/{d} dwords(root/nested)={d}/{d} depth={d} classes(state/draw/wait/indirect/memory/event/control/extension/unknown/filler)={d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}/{d} indirect(cycles/budget)={d}/{d}\n",
        .{
            summary.root_packets,
            summary.nested_packets,
            summary.executed_packets,
            summary.executed_root_packets,
            summary.executed_nested_packets,
            summary.root_dwords,
            summary.nested_dwords,
            summary.max_depth,
            summary.classCount(.state),
            summary.classCount(.draw),
            summary.classCount(.wait),
            summary.classCount(.indirect),
            summary.classCount(.memory),
            summary.classCount(.event),
            summary.classCount(.control),
            summary.classCount(.emulator_extension),
            summary.classCount(.unknown),
            summary.classCount(.filler),
            execution.indirect_cycles,
            execution.indirect_budget_limited,
        },
    );
    machoCapturePrint(
        "macho-processor: XENOS PACKET TRACE EXECUTED: classes(state/draw/wait/indirect/memory/event/control/extension/unknown/filler)={d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}/{d} last={s}/0x{x} last_source={s} last_offset={d} last_executed={s}\n",
        .{
            summary.executedClassCount(.state),
            summary.executedClassCount(.draw),
            summary.executedClassCount(.wait),
            summary.executedClassCount(.indirect),
            summary.executedClassCount(.memory),
            summary.executedClassCount(.event),
            summary.executedClassCount(.control),
            summary.executedClassCount(.emulator_extension),
            summary.executedClassCount(.unknown),
            summary.executedClassCount(.filler),
            last_class,
            last_opcode,
            if (summary.last) |last| last.source.label() else "none",
            if (summary.last) |last| last.dword_offset else 0,
            if (summary.last) |last| if (last.executed) "YES" else "NO" else "NO",
        },
    );
}

pub fn executeRetainedBatch(
    self: anytype,
    bytes: []const u8,
    root_start: u32,
    root_dwords: u32,
    ring_dwords: u32,
    authentic: bool,
    authority_batch_id: u64,
) void {
    const at = self.executed_steps;
    const ledger = &self.gpu_vd_swap_contract;
    const executor_stages = [_]gpu.VdSwapStage{
        .pm4_state_programmed,
        .draw_submitted,
        .draw_consumed,
        .render_target_state_observed,
        .render_target_memory_observed,
        .draw_completion_signaled,
        .fetch_constant_decoded,
        .xe_swap_candidate_seen,
        // The executor is the only route that can name a front buffer from
        // an executed batch rather than from a byte pattern. Leaving the
        // stage off this list is what let it read `not_attempted` for a
        // whole run while every stage beside it recorded a drained input.
        .frontbuffer_validated,
    };

    if (root_dwords == 0) {
        for (executor_stages) |stage| {
            ledger.recordStarvation(stage, .stateful_pm4_execution, .input_empty, .input_drained, 0, at);
        }
        return;
    }
    if (self.gpu_xenos_last_payload_epoch == self.gpu_ring_publication.advances) return;
    self.gpu_xenos_last_payload_epoch = self.gpu_ring_publication.advances;

    // Read-only replay, and this is not a detail.
    //
    // The batch has already been consumed by the emulator's own command
    // processor, which means its MEM_WRITE and EVENT_WRITE_SHD packets have
    // already landed in guest memory.  Replaying them would make Rosette
    // write stale fence and progress values over addresses the guest has
    // since advanced — Rosette would become the corrupting writer, and the
    // corruption would look like a title bug.  The span-gated path can
    // safely attach the write callback because it executes an *outstanding*
    // span whose writes have not happened yet; this path cannot.
    //
    // Nothing needed here is lost.  The register file, draw state, EDRAM
    // resolves and completion events all live in Rosette's own storage, and
    // suppressed writes are counted rather than dropped silently, so the
    // batch's memory-write content stays visible as a number.
    const deferred_before = self.gpu_xenos_runtime.executor.deferred_memory_count;
    self.gpu_xenos_runtime.attachMemory(self, xenosMemoryRead, self, null);
    // Restored on every exit path.  Leaving the runtime read-only would
    // silently suppress the writes of the outstanding-span path, whose
    // batch has not been consumed yet and whose writes must land — and a
    // suppressed write there would look like a title that stopped
    // signalling rather than a callback this function unhooked.
    defer self.gpu_xenos_runtime.attachMemory(self, xenosMemoryRead, self, xenosMemoryWrite);
    const execution = self.gpu_xenos_runtime.inspectRetainedRingBytes(
        bytes,
        root_start,
        root_dwords,
        ring_dwords,
    ) catch |err| {
        self.gpu_xenos_retained_refusals +|= 1;
        // A refusal is not an empty input, and it is not unreadable
        // memory either: the walk had dwords, they read back fine, and
        // the decoder rejected how they were framed. Naming it
        // `memory-unreadable` sent the reader to the memory view for a
        // window problem.
        for (executor_stages) |stage| {
            ledger.recordStarvation(stage, .stateful_pm4_execution, .input_unavailable, .decoder_refused_framing, root_dwords, at);
        }
        machoCapturePrint(
            "macho-processor: XENOS RETAINED BATCH refused: error={s} start={d} dwords={d} ring_dwords={d}; the producer's retained dwords exist and the command processor could not decode them, which is a framing defect rather than an absent batch\n",
            .{ @errorName(err), root_start, root_dwords, ring_dwords },
        );
        return;
    };
    const deferred_writes = self.gpu_xenos_runtime.executor.deferred_memory_count - deferred_before;

    self.gpu_xenos_retained_executions +|= 1;
    self.observeGpuEarlyPacketExecution(execution, authentic);
    const executed_packets = execution.packets_after - execution.packets_before;
    // Credit the execution once under the retained root's stable identity.
    // Every later frontier report is only another observation of these
    // units, so it cannot turn this run's 24 draws into 148×24 draws.
    const root_byte_start = @as(usize, root_start) * 4;
    const root_byte_length = @as(usize, root_dwords) * 4;
    var payload_digest: u64 = if (root_byte_start <= bytes.len and
        root_byte_length <= bytes.len - root_byte_start)
        std.hash.Wyhash.hash(0, bytes[root_byte_start .. root_byte_start + root_byte_length])
    else
        std.hash.Wyhash.hash(0, std.mem.asBytes(&root_dwords));
    if (payload_digest == 0) payload_digest = 1;
    self.recordPm4AuthorityExecution(authority_batch_id, execution, .replay);
    const credit_run = if (self.event_stream.run_id == 0) @as(u64, 1) else self.event_stream.run_id;
    const credit_stream = if (self.gpu_ring_watch_base != 0) self.gpu_ring_watch_base else @as(u64, root_start) + 1;
    const credit_generation = @max(self.gpu_ring_publication.advances, 1);
    const credit_sequence = @max(self.gpu_xenos_retained_executions, 1);
    const Work = struct {
        kind: gpu.work_credit.Kind,
        units: u64,
    };
    const executed_work = [_]Work{
        .{ .kind = .pm4_batch, .units = execution.dwords },
        .{ .kind = .pm4_packet, .units = executed_packets },
        .{ .kind = .draw_submission, .units = execution.draws },
        .{ .kind = .completion_signal, .units = execution.draw_completion_signals },
    };
    for (executed_work) |work| {
        if (work.units == 0) continue;
        _ = self.cocoa_graphics.claimExecutedWork(.{
            .key = .{
                .run = credit_run,
                .producer = .xenia_host,
                .stream = credit_stream,
                .generation = credit_generation,
                .sequence = credit_sequence,
                .kind = work.kind,
            },
            .units = work.units,
            .payload_digest = payload_digest,
            .step = at,
        });
    }
    const target = self.gpu_xenos_runtime.renderTargetEvidence();
    const runtime_fetch = self.gpu_xenos_runtime.frontBufferFetch();
    const runtime_swap = self.gpu_xenos_runtime.last_swap;
    const semantic_sequence_base = credit_sequence *% 4;
    if (execution.draws != 0) {
        _ = self.cocoa_graphics.observeIntent(.{
            .run = credit_run,
            .boundary = .{ .decoded_pm4 = .{ .packet_class = .draw, .header = 0 } },
            .producer = .xenia_host,
            .evidence = .completed_call,
            .source_identity = credit_stream,
            .generation = credit_generation,
            .sequence = semantic_sequence_base +% 1,
        });
    }
    if (target.state_observed) {
        _ = self.cocoa_graphics.observeIntent(.{
            .run = credit_run,
            .boundary = .{ .decoded_pm4 = .{ .packet_class = .register_write, .header = 0 } },
            .producer = .xenia_host,
            .evidence = .completed_call,
            .source_identity = credit_stream,
            .generation = credit_generation,
            .sequence = semantic_sequence_base +% 2,
        });
    }
    if (execution.swaps != 0) {
        _ = self.cocoa_graphics.observeIntent(.{
            .run = credit_run,
            .boundary = .{ .decoded_pm4 = .{ .packet_class = .xe_swap, .header = 0 } },
            .producer = .guest_title,
            .evidence = .completed_call,
            .source_identity = credit_stream,
            .generation = credit_generation,
            .sequence = semantic_sequence_base +% 3,
        });
    }

    // Each of these is recorded whether or not it was found.  The negative
    // outcome is the valuable one: it is the difference between "the
    // command processor executed this batch and it programmed no colour
    // target" and "nothing ever looked at the colour target".
    ledger.observeProbe(.pm4_state_programmed, .stateful_pm4_execution, executed_packets != 0, executed_packets, at);
    ledger.observeProbe(.draw_submitted, .stateful_pm4_execution, execution.draws != 0, execution.draws, at);
    ledger.observeProbe(.draw_consumed, .stateful_pm4_execution, execution.draws != 0, execution.draws, at);
    ledger.observeProbe(.render_target_state_observed, .xenos_register_file, target.state_observed, target.raw_color_info, at);
    ledger.observeProbe(
        .render_target_memory_observed,
        .xenos_register_file,
        self.gpu_xenos_runtime.color_resolve_observations != 0,
        self.gpu_xenos_runtime.color_resolve_observations,
        at,
    );
    // The executor's own account of the same two stages.
    //
    // Both were recorded against the register file alone, read after the
    // fact, and against `stateful-pm4-execution` only on the paths where
    // the executor *failed*. So a batch that executed cleanly left its own
    // probe reading `not-attempted` — the sole source of render-target
    // state, silent about what it had just done. The register file answers
    // "is a target configured now"; these answer "did this batch program
    // one", and the frontier is asking the second question.
    ledger.observeProbe(
        .render_target_state_observed,
        .stateful_pm4_execution,
        execution.render_target_register_writes != 0,
        execution.render_target_register_writes,
        at,
    );
    ledger.observeProbe(
        .render_target_memory_observed,
        .stateful_pm4_execution,
        execution.color_resolves != 0,
        execution.color_resolves,
        at,
    );
    ledger.observeProbe(
        .draw_completion_signaled,
        .stateful_pm4_execution,
        execution.draw_completion_signals != 0,
        execution.draw_completion_signals,
        at,
    );
    ledger.observeProbe(.fetch_constant_decoded, .xenos_register_file, runtime_fetch != null, execution.dwords, at);
    ledger.observeProbe(
        .fetch_constant_decoded,
        .stateful_pm4_execution,
        runtime_fetch != null,
        execution.register_writes,
        at,
    );
    ledger.observeProbe(.xe_swap_candidate_seen, .stateful_pm4_execution, execution.swaps != 0, execution.dwords, at);
    // The executor's own answer about the front buffer: a batch it ran
    // either named a surface or it did not. `runtime_swap` is that surface,
    // and a null one after a real execution is a finding about the batch
    // rather than a hole in the observer.
    ledger.observeProbe(
        .frontbuffer_validated,
        .stateful_pm4_execution,
        runtime_swap != null,
        execution.swaps,
        at,
    );

    ledger.observePacket(.{
        .projection_readable = true,
        .stream_observed = execution.dwords != 0 or executed_packets != 0,
        .stream_validated = (execution.dwords != 0 or executed_packets != 0) and !execution.truncated,
        .candidate_seen = execution.swaps != 0 or runtime_swap != null,
        .readable = runtime_swap != null,
        .decoded = runtime_swap != null,
        .swap = runtime_swap,
        .fetch = runtime_fetch,
        .fetch_decoded = runtime_fetch != null,
        .root_packets = executed_packets,
        .draw_packets = execution.draws,
        .swap_packets = execution.swaps,
        .truncated = execution.truncated,
        .unknown_opcodes = execution.unknown_opcodes,
        .dwords_examined = execution.dwords,
        .dwords_scanned = execution.dwords,
        .span_dwords = root_dwords,
        .authentic_consumption = runtime_swap != null and
            authentic and
            self.gpu_ring_injection.injections == 0,
    }, at, .stateful_pm4_executor);

    ledger.observeIntermediary(.{
        .render_target_state_observed = target.state_observed,
        .render_target_memory_observed = self.gpu_xenos_runtime.color_resolve_observations != 0,
        .draw_completion_signaled = execution.draw_completion_signals != 0,
    }, at, .xenos_runtime);

    machoCapturePrint(
        "macho-processor: XENOS RETAINED BATCH: disposition={s} epoch={d} start={d} dwords={d} packets={d} draws={d} renderable_draws={d} events={d} swaps={d} unknown={d} truncated={s} indirect(buffers/read/requested)={d}/{d}/{d} status={s}; target(state/color/depth/surface)={s}/0x{x:0>8}/0x{x:0>8}/0x{x:0>8} resolves={d} draw_completions(observed/published)={d}/{d} fetch={s} guest_writes_suppressed={d}; retained PM4 reconstructs Rosette-owned state only. The emulator already consumed this batch, so interrupts, waits and guest memory are not replayed\n",
        .{
            execution.disposition.label(),
            self.gpu_ring_publication.advances,
            root_start,
            root_dwords,
            executed_packets,
            execution.draws,
            execution.renderable_draw_observations,
            execution.events,
            execution.swaps,
            execution.unknown_opcodes,
            if (execution.truncated) "YES" else "NO",
            execution.indirect_buffers,
            execution.indirect_dwords_read,
            execution.indirect_dwords_requested,
            execution.indirect_last_status.label(),
            if (target.state_observed) "YES" else "NO",
            target.raw_color_info,
            target.raw_depth_info,
            target.raw_surface_info,
            self.gpu_xenos_runtime.color_resolve_observations,
            execution.draw_completion_observations,
            execution.draw_completion_signals,
            if (runtime_fetch != null) "decoded" else "absent",
            deferred_writes,
        },
    );

    if (execution.rectangle_draws != 0) {
        const route = if (execution.rectangle_backend) |backend| backend.label() else "none";
        const rejection = if (execution.rectangle_rejection) |reason| reason.label() else "none";
        const plan = execution.rectangle_plan;
        machoCapturePrint(
            "macho-processor: XENOS RETAINED BATCH rectangle backend: observed={d} lowered={d} empty={d} rejected={d} host_indices={d} trailing_vertices={d} route={s} rejection={s} plan(guest_vertices/rectangles/topology/vertex/geometry/index_format/index_count/restart/builtin)={d}/{d}/{s}/{s}/{s}/{s}/{d}/{s}/{s}; plan is diagnostic/reconstructive because Xenia already consumed this batch\n",
            .{
                execution.rectangle_draws,
                execution.rectangle_draws_lowered,
                execution.rectangle_draws_empty,
                execution.rectangle_draws_rejected,
                execution.rectangle_host_indices,
                execution.rectangle_trailing_vertices,
                route,
                rejection,
                if (plan) |value| value.guest_vertex_count else 0,
                if (plan) |value| value.rectangle_count else 0,
                if (plan) |value| @tagName(value.host_topology) else "none",
                if (plan) |value| value.host_vertex_shader.label() else "none",
                if (plan) |value| value.host_geometry_shader.label() else "none",
                if (plan) |value| @tagName(value.host_index_format) else "none",
                if (plan) |value| value.host_index_count else 0,
                if (plan) |value| if (value.host_primitive_restart) "YES" else "NO" else "NO",
                if (plan) |value| if (value.uses_builtin_index_buffer) "YES" else "NO" else "NO",
            },
        );
    }

    if (runtime_swap) |swap| {
        if (swap.plausible()) {
            self.gpu_frontbuffer = swap;
            ledger.observeFrontBuffer(swap, .stateful_pm4_executor, at);
            self.offerGuestFrontBuffer(swap, runtime_fetch, false);
            machoCapturePrint(
                "macho-processor: XENOS RETAINED BATCH present handoff: frontbuffer=0x{x:0>8} extent={d}x{d} fetch={s}\n",
                .{
                    swap.frontbuffer_physical_address,
                    swap.width,
                    swap.height,
                    if (runtime_fetch != null) "observed" else "absent (defaults apply)",
                },
            );
        }
    }

    // This batch was already consumed by Xenia. Observing its draw packets
    // does not grant Rosette ownership to publish or dispatch a second
    // completion, regardless of which callback domains are registered.
    ledger.recordStarvation(
        .draw_completion_dispatched,
        .interrupt_dispatch,
        if (execution.draw_completion_observations != 0) .refused_by_owner else .input_empty,
        .input_drained,
        execution.draw_completion_observations,
        at,
    );
}

pub fn recordRingSurveyStarvation(
    self: anytype,
    outcome: gpu.VdSwapProbeOutcome,
    cause: gpu.VdSwapStarvationCause,
) void {
    const at = self.executed_steps;
    const ledger = &self.gpu_vd_swap_contract;
    const ring_stages = [_]gpu.VdSwapStage{
        .ring_projection_readable,
        .pm4_stream_observed,
        .pm4_stream_validated,
        .xe_swap_candidate_seen,
    };
    const ring_probes = [_]gpu.VdSwapProbe{
        .ring_projection_survey,
        .outstanding_span_scan,
        .retained_batch_scan,
        .nested_indirect_walk,
        .stateful_pm4_execution,
    };
    for (ring_stages) |stage| {
        for (ring_probes) |probe| {
            ledger.recordStarvation(stage, probe, outcome, cause, 0, at);
        }
    }
    const additional = [_]struct { stage: gpu.VdSwapStage, probe: gpu.VdSwapProbe }{
        .{ .stage = .xe_swap_packet_readable, .probe = .ring_projection_survey },
        .{ .stage = .xe_swap_packet_readable, .probe = .outstanding_span_scan },
        .{ .stage = .xe_swap_packet_decoded, .probe = .ring_projection_survey },
        .{ .stage = .xe_swap_packet_decoded, .probe = .outstanding_span_scan },
        .{ .stage = .fetch_constant_decoded, .probe = .outstanding_span_scan },
        .{ .stage = .frontbuffer_validated, .probe = .retained_batch_scan },
    };
    for (additional) |entry| ledger.recordStarvation(entry.stage, entry.probe, outcome, cause, 0, at);
}

pub fn recordRetainedBatchStarvation(
    self: anytype,
    outcome: gpu.VdSwapProbeOutcome,
    cause: gpu.VdSwapStarvationCause,
) void {
    const at = self.executed_steps;
    const ledger = &self.gpu_vd_swap_contract;
    const starved = [_]struct { stage: gpu.VdSwapStage, probe: gpu.VdSwapProbe }{
        .{ .stage = .pm4_state_programmed, .probe = .stateful_pm4_execution },
        .{ .stage = .draw_submitted, .probe = .stateful_pm4_execution },
        .{ .stage = .draw_consumed, .probe = .stateful_pm4_execution },
        .{ .stage = .render_target_state_observed, .probe = .stateful_pm4_execution },
        .{ .stage = .render_target_state_observed, .probe = .xenos_register_file },
        .{ .stage = .render_target_memory_observed, .probe = .stateful_pm4_execution },
        .{ .stage = .render_target_memory_observed, .probe = .xenos_register_file },
        .{ .stage = .draw_completion_signaled, .probe = .stateful_pm4_execution },
        .{ .stage = .fetch_constant_decoded, .probe = .stateful_pm4_execution },
        .{ .stage = .fetch_constant_decoded, .probe = .xenos_register_file },
        .{ .stage = .xe_swap_candidate_seen, .probe = .stateful_pm4_execution },
        .{ .stage = .xe_swap_packet_readable, .probe = .retained_batch_scan },
        .{ .stage = .xe_swap_packet_decoded, .probe = .retained_batch_scan },
        .{ .stage = .frontbuffer_validated, .probe = .retained_batch_scan },
    };
    for (starved) |entry| ledger.recordStarvation(entry.stage, entry.probe, outcome, cause, 0, at);
}

pub fn logRingPayload(self: anytype, chosen: gpu.ring_view.Reading) void {
    const bytes = self.guestMemoryConst(chosen.address, self.gpu_ring_watch_size) orelse {
        // The projection the survey chose cannot be read back.  Every
        // retained-batch probe is unavailable rather than empty, and the
        // difference decides whether the gaps below belong to Rosette's
        // memory mapping or to the title.
        self.recordRetainedBatchStarvation(.input_unavailable, .memory_unreadable);
        return;
    };
    const ring_dwords: u32 = @intCast(@min(self.gpu_ring_watch_size / 4, std.math.maxInt(u32)));
    // Bounded like every other checkpoint walk. A ring configured at the
    // emulator's largest size is half a million dwords, and this runs on a
    // heartbeat in a ReleaseFast build where nothing else caps it.
    const written = gpu.ring_payload.digest(bytes, ring_dwords, gpu.ring_scan.max_search_dwords);
    var indirect_packets: u64 = 0;
    var indirect_draws: u64 = 0;
    var indirect_swaps: u64 = 0;
    self.xenia_gpu_causal_trace.observeRingPayload(
        written.real_packets,
        written.draws,
        written.swaps,
        self.executed_steps,
        self.gpu_ring_injection.injections == 0,
    );
    if (written.run_count == 0) {
        // A readable ring holding no written run at all.  The walk had
        // somewhere to look and nothing to look at.
        self.recordRetainedBatchStarvation(.input_empty, .input_drained);
    }
    if (written.run_count != 0) {
        // A drained primary span has equal read/write pointers, but the
        // retained ring still contains the exact batch the command
        // processor consumed.  Build the smallest envelope around the
        // written runs so a root INDIRECT_BUFFER packet can be followed
        // without pretending the whole ring is a live outstanding span.
        const root_start = written.runs[0].start;
        var root_end: u32 = root_start;
        var run_index: u32 = 0;
        while (run_index < written.run_count) : (run_index += 1) {
            const written_run = written.runs[run_index];
            const end = written_run.start +| written_run.length;
            if (end > root_end) root_end = end;
        }
        if (root_end <= root_start or root_start >= ring_dwords) {
            self.recordRetainedBatchStarvation(.input_empty, .input_drained);
        }
        if (root_end > root_start and root_start < ring_dwords) {
            const content_count = @min(root_end - root_start, ring_dwords - root_start);
            // Hand the decoder whole packets, not whole *content*.
            //
            // The envelope above is built from non-zero runs, and a PM4
            // payload may legitimately contain a zero dword — so the
            // envelope can end inside a packet. On 2026-09-01 it ended
            // fourteen dwords in, the stateful executor read a header
            // declaring more than it had been given, refused the entire
            // batch with `TruncatedRing`, and every render-target stage
            // below it read zero for the remaining five billion steps.
            // The executor is the only source of those registers, so the
            // acceptance board's G4 was unjudgeable because of a window.
            const framed = gpu.ring_payload.framedExtent(
                bytes,
                ring_dwords,
                root_start,
                content_count,
                gpu.ring_scan.max_search_dwords,
            );
            const root_count = framed.dwords;
            if (framed.widensContentWindow()) {
                machoCapturePrint(
                    "macho-processor: XENOS RETAINED WINDOW widened: start={d} content_dwords={d} framed_dwords={d} packets={d} beyond_content={d} truncated_by_ring={s} ring_dwords={d}; the non-zero envelope ended inside a packet, so the decoder would have been handed a header declaring more dwords than the window held. The window now covers whole packets and the extra dwords are payload the producer wrote, not ring the walk invented\n",
                    .{
                        root_start,
                        content_count,
                        framed.dwords,
                        framed.packets,
                        framed.packets_beyond_content,
                        if (framed.truncated_by_ring) "YES" else "NO",
                        ring_dwords,
                    },
                );
            }
            const consumed = self.xenia_gpu_handoff.pm4_packets != 0 or
                self.execution_tracepoints.roleEntered(.command_processor);
            const authentic = self.gpu_ring_injection.injections == 0 and
                self.gpu_ring_publication.published();
            const indirect = self.xenia_gpu_causal_trace.observePm4SpanWithIndirects(
                bytes,
                root_start,
                root_count,
                ring_dwords,
                @max(self.gpu_ring_publication.advances, 1),
                self.executed_steps,
                consumed,
                authentic,
                self,
                xenosMemoryRead,
            );
            const authority_batch_id = self.pm4BatchIdentity(
                bytes,
                root_start,
                root_count,
                ring_dwords,
                indirect.content_fingerprint,
            );
            const authority_source: gpu.pm4_authority.SourceClass = if (authentic)
                .guest_authentic
            else if (self.gpu_ring_injection.injections != 0)
                .synthetic
            else
                .host_forwarded;
            self.recordPm4AuthorityWalk(authority_batch_id, indirect, authority_source);
            indirect_packets = @as(u64, indirect.root_packets) + @as(u64, indirect.nested_packets);
            indirect_draws = indirect.draw_packets;
            indirect_swaps = indirect.swap_packets;
            // The walker gives us stream and indirect-reference truth, but
            // it does not retain a contiguous payload for every indirect
            // address. In particular, seeing an XE_SWAP opcode here must
            // never be promoted to "packet readable" or "decoded".
            self.gpu_vd_swap_contract.observePacket(.{
                .projection_readable = true,
                .stream_observed = indirect.packets_walked != 0,
                .stream_validated = indirect.packets_walked != 0 and
                    !indirect.root_truncated and
                    !indirect.packet_budget_exhausted and
                    indirect.invalid_references == 0 and
                    indirect.cycle_references == 0 and
                    indirect.depth_limited_references == 0 and
                    indirect.truncated_references == 0 and
                    indirect.budget_limited_references == 0,
                .indirects_resolved = indirect.unreadable_references == 0 and
                    indirect.invalid_references == 0 and
                    indirect.cycle_references == 0 and
                    indirect.depth_limited_references == 0 and
                    indirect.truncated_references == 0 and
                    indirect.budget_limited_references == 0,
                .candidate_seen = indirect_swaps != 0,
                .nested_packets = indirect.nested_packets,
                .indirect_packets = indirect.indirect_packets,
                .draw_packets = indirect.draw_packets,
                .swap_packets = indirect_swaps,
                .truncated = indirect.root_truncated or indirect.truncated_references != 0,
                .unreadable_references = indirect.unreadable_references,
                .dwords_examined = root_count,
                .span_dwords = root_count,
            }, self.executed_steps, .nested_pm4_walk);
            const walked = indirect.packets_walked;
            self.gpu_vd_swap_contract.observeProbe(.pm4_stream_observed, .nested_indirect_walk, walked != 0, root_count, self.executed_steps);
            self.gpu_vd_swap_contract.observeProbe(.pm4_indirects_resolved, .nested_indirect_walk, indirect.unreadable_references == 0 and indirect.invalid_references == 0 and indirect.cycle_references == 0, indirect.indirect_references, self.executed_steps);
            self.gpu_vd_swap_contract.observeProbe(.draw_submitted, .nested_indirect_walk, indirect_draws != 0, indirect_draws, self.executed_steps);
            // The walk follows every indirect buffer the batch names, so a
            // zero here means no XE_SWAP exists anywhere the producer
            // pointed — the strongest form this absence takes.
            self.gpu_vd_swap_contract.observeProbe(.xe_swap_candidate_seen, .nested_indirect_walk, indirect_swaps != 0, walked, self.executed_steps);
            // The nested walk has told us what the batch contains.  Hand
            // the same envelope to the stateful command processor so the
            // register file, the completion queue and the fetch constant
            // are readings rather than blanks.  Without this the executor
            // only ever runs on an outstanding span, which a drained ring
            // never has.
            self.executeRetainedBatch(
                bytes,
                root_start,
                root_count,
                ring_dwords,
                authentic,
                authority_batch_id,
            );
            if (indirect_draws != 0) {
                self.gpu_ring_draws_seen = true;
                const draw_count: u32 = @intCast(@min(indirect_draws, @as(u64, std.math.maxInt(u32))));
                if (draw_count > self.gpu_ring_draws_last_count) self.gpu_ring_draws_last_count = draw_count;
            }
            if (consumed) {
                const consumed_packets = if (indirect_packets > @as(u64, written.real_packets)) indirect_packets else @as(u64, written.real_packets);
                const consumed_draws = if (indirect_draws > @as(u64, written.draws)) indirect_draws else @as(u64, written.draws);
                const consumed_swaps = if (indirect_swaps > @as(u64, written.swaps)) indirect_swaps else @as(u64, written.swaps);
                self.gpu_ring_publication.observeConsumedBatch(
                    root_count,
                    consumed_packets,
                    consumed_draws,
                    consumed_swaps,
                    self.executed_steps,
                );
            }
            machoCapturePrint(
                "macho-processor: PM4 INDIRECT WALK: root_start={d} root_dwords={d} consumed={s} authentic={s} root_packets={d} nested_packets={d} refs={d} readable={d} unreadable={d} truncated_refs={d} budget_refs={d} draws(root/nested/total)={d}/{d}/{d} swaps(root/nested/total)={d}/{d}/{d} cycles={d} truncated={s}\n",
                .{
                    root_start,
                    root_count,
                    if (consumed) "YES" else "NO",
                    if (authentic) "YES" else "NO",
                    indirect.root_packets,
                    indirect.nested_packets,
                    indirect.indirect_references,
                    indirect.readable_references,
                    indirect.unreadable_references,
                    indirect.truncated_references,
                    indirect.budget_limited_references,
                    indirect.root_draw_packets,
                    indirect.nested_draw_packets,
                    indirect.draw_packets,
                    indirect.root_swap_packets,
                    indirect.nested_swap_packets,
                    indirect.swap_packets,
                    indirect.cycle_references,
                    if (indirect.root_truncated) "YES" else "NO",
                },
            );
        }
    }
    const walked_draws: u32 = @intCast(@min(indirect_draws, @as(u64, std.math.maxInt(u32))));
    const walked_swaps: u32 = @intCast(@min(indirect_swaps, @as(u64, std.math.maxInt(u32))));
    // The indirect walk includes root packets as well as nested packets;
    // it is therefore a complete walked total, not an increment to add to
    // the root-only digest. Taking the maximum avoids counting a root
    // draw twice while still retaining nested draws the root digest could
    // not see.
    const effective_draws: u32 = if (written.draws > walked_draws) written.draws else walked_draws;
    const effective_swaps: u32 = if (written.swaps > walked_swaps) written.swaps else walked_swaps;
    const payload_verdict = if (effective_swaps != 0)
        "the payload contains a present request"
    else if (effective_draws != 0)
        "the payload contains draws, including indirect buffers, but no present request"
    else
        "the retained payload contains no decoded draw or present request";
    machoCapturePrint(
        "macho-processor: RING PAYLOAD: projection={s} nonzero_dwords={d} runs={d} (dropped={d}) real_packets={d} root_draws={d} root_swaps={d} indirect_packets={d} indirect_draws={d} indirect_swaps={d} total_draws={d} total_swaps={d} scanned={d}; {s}; {s}\n",
        .{
            chosen.projection.label(),
            written.nonzero_dwords,
            written.run_count,
            written.runs_dropped,
            written.real_packets,
            written.draws,
            written.swaps,
            indirect_packets,
            indirect_draws,
            indirect_swaps,
            effective_draws,
            effective_swaps,
            written.scanned_dwords,
            written.verdict(),
            payload_verdict,
        },
    );
    var run_index: u32 = 0;
    while (run_index < written.run_count) : (run_index += 1) {
        const region = written.runs[run_index];
        var dwords: [gpu.ring_payload.max_dump_dwords]u32 = undefined;
        const count = gpu.ring_payload.dumpRun(bytes, ring_dwords, region, &dwords);
        const header = region.first_header orelse gpu.Pm4Header{ .raw = 0, .kind = .type2, .count = 0 };
        machoCapturePrint(
            "  run #{d} start_dword={d} length={d} frames_cleanly={s} first_packet={s} opcode={s} declared_dwords={d}\n",
            .{
                run_index + 1,
                region.start,
                region.length,
                if (region.frames_cleanly) "YES" else "NO",
                @tagName(header.kind),
                if (header.kind == .type3) header.opcode.label() else "-",
                header.totalDwords(),
            },
        );
        var at: u32 = 0;
        while (at < count) : (at += 8) {
            const end = @min(at + 8, count);
            var line: [160]u8 = undefined;
            var used: usize = 0;
            var column = at;
            while (column < end) : (column += 1) {
                const piece = std.fmt.bufPrint(line[used..], "{x:0>8} ", .{dwords[column]}) catch break;
                used += piece.len;
            }
            machoCapturePrint("    +{d: <5} {s}\n", .{ region.start + at, line[0..used] });
        }
    }
}

pub fn refreshDeadlockPredictor(self: anytype) void {
    if (self.xenia_memory_views.ready()) {
        self.sync_object_identity.observeMappingBase(self.xenia_memory_views.mapping_base);
    }
    const ledger = &self.deadlock_predictor;
    for (&self.pthreads.threads) |*thread| {
        if (!thread.active) continue;
        const parked = switch (thread.state) {
            .waiting_mutex,
            .waiting_condvar,
            .waiting_semaphore,
            .waiting_event,
            .waiting_futex_address,
            .waiting_join,
            => true,
            else => false,
        };
        const kind: deadlock_predictor.ObjectKind = switch (thread.state) {
            .waiting_mutex => .mutex,
            .waiting_condvar => .condvar,
            .waiting_semaphore => .semaphore,
            .waiting_event => .event,
            .waiting_join => .thread_join,
            else => .unknown,
        };
        const object = if (thread.wait_address != 0)
            thread.wait_address
        else if (thread.waiting_condvar != 0)
            thread.waiting_condvar
        else
            thread.waiting_mutex;
        const state: deadlock_predictor.ThreadState = if (parked)
            .waiting
        else if (thread.state == .terminated or thread.state == .cancelled)
            .terminated
        else
            .running;
        if (parked and object != 0) ledger.observeObject(object, kind);
        ledger.observeThreadContext(.{
            .handle = thread.handle,
            .state = state,
            .waiting_on = object,
            .blocked_since_step = thread.blocked_since_step,
            .blocked_rip = thread.blocked_rip,
            .start_routine = thread.start_routine,
            .waiting_mutex = thread.waiting_mutex,
            .wait_generation = thread.wait_generation,
            .notified_generation = thread.notified_generation,
            .blocked_reason = thread.blocked_reason,
        });
    }
    for (&self.pthreads.waits.objects) |*object| {
        if (!object.active) continue;
        if (object.notifications != 0) {
            ledger.observeNotifyAt(
                object.address,
                .condvar,
                object.last_notify_thread,
                object.last_notify_pc,
                object.last_notify_step,
            );
        }
        // A granted repair is a fact about the object that the ledger
        // cannot derive from notifications: a spurious wake is Rosette
        // manufacturing a wake, not the guest signalling. Carried over so
        // the deadlock report can distinguish "nobody ever signalled it"
        // from "we woke it once and it re-parked, so the wait is
        // genuinely unsatisfied".
        if (object.repair_attempts != 0) {
            ledger.observeRepair(object.address, object.repair_attempts);
        }
    }
    ledger.refresh(self.executed_steps);
}

pub fn refreshStallRelease(self: anytype) void {
    const ledger = &self.stall_release;
    const progress = self.stallReleaseProgress();

    // Settle what is outstanding first: an attempt judged against the state
    // that provoked the next one would attribute the wrong outcome.
    var index: usize = 0;
    while (index < ledger.count) : (index += 1) {
        const object = ledger.attempts[index].object;
        var re_parked = false;
        for (&self.pthreads.threads) |*thread| {
            if (!thread.active) continue;
            if (thread.waiting_condvar != object and thread.wait_address != object) continue;
            if (thread.state == .waiting_condvar) re_parked = true;
        }
        ledger.settle(object, progress, re_parked, self.executed_steps);
    }

    // A release that provably re-parked names the defect as guest-side, and
    // the waiter's own state is the only thing that makes that actionable.
    // Fetch it once per attempt: resolution, the object's ledger numbers,
    // the waiting threads, and a probe of the bytes at the object when they
    // are readable.
    for (ledger.attempts[0..ledger.count]) |attempt| {
        if (attempt.outcome != .predicate_unsatisfied or attempt.state_fetched) continue;
        self.fetchStallReleaseState(attempt.object);
        ledger.markStateFetched(attempt.object);
    }
}

pub fn fetchStallReleaseState(self: anytype, object: u64) void {
    // The synchronisation history this runtime keeps for the object, if it
    // has one. The repairs count is the ledger's own answer to "did we
    // already wake it and it re-parked" — the fact that separates a lost
    // wakeup from a genuinely unsatisfied predicate.
    var notifications: u64 = 0;
    var repairs: u32 = 0;
    var first_wait_step: u64 = 0;
    if (self.pthreads.waits.find(object)) |entry| {
        notifications = entry.notifications;
        repairs = entry.repair_attempts;
        first_wait_step = entry.first_wait_step;
    }

    // Where the object lives. A guest console address translates through
    // the emulator's memory view; anything else is a host-side primitive
    // whose waiter-visible predicate lives inside the guest, not here.
    var resolution: []const u8 = "host-side primitive";
    var host: u64 = object;
    if (object <= std.math.maxInt(u32)) {
        if (self.xenia_memory_views.virtualHostAddress(object)) |translated| {
            host = translated;
            resolution = "guest console address";
        }
    }

    // The waiting threads, from the scheduler's own tables, and the kind
    // they imply. A condvar waiter parks with a `waiting_condvar`; other
    // waiters carry a `wait_address`.
    var kind: []const u8 = "wait object";
    var waiter_handles: [64]u64 = undefined;
    var waiter_count: usize = 0;
    var longest_park: u64 = 0;
    for (&self.pthreads.threads) |*thread| {
        if (!thread.active) continue;
        const on_this = thread.waiting_condvar == object or thread.wait_address == object;
        if (!on_this) continue;
        if (thread.state == .waiting_condvar) kind = "condvar";
        if (waiter_count < waiter_handles.len) {
            waiter_handles[waiter_count] = thread.handle;
            waiter_count += 1;
        }
        longest_park = @max(longest_park, thread.blocked_since_step);
    }
    const parked_steps = if (longest_park != 0) self.executed_steps -| longest_park else 0;

    // Probe the bytes at the object when the emulator's memory view covers
    // them. Five dwords is enough to show an event's signal state or a
    // queue's head fields without turning the report into a memory dump.
    var probed = false;
    var dwords: [5]u32 = undefined;
    if (self.guestMemoryConst(host, 20)) |bytes| {
        for (0..5) |index| dwords[index] = std.mem.readInt(u32, bytes[index * 4 ..][0..4], .little);
        probed = true;
    }

    machoCapturePrint(
        "macho-processor: STALL RELEASE STATE: object=0x{x} kind={s} resolution={s} waiters={d} notifications={d} repairs={d} parked_steps={d} step={d}; a spurious wake already proved this predicate unsatisfied — the code that should have published the state it waits on never ran\n",
        .{
            object,        kind,    resolution,   waiter_count,
            notifications, repairs, parked_steps, self.executed_steps,
        },
    );
    if (probed) {
        machoCapturePrint(
            "  bytes at 0x{x}: q0=0x{x:0>8} q1=0x{x:0>8} q2=0x{x:0>8} q3=0x{x:0>8} q4=0x{x:0>8} {s}\n",
            .{
                host, dwords[0], dwords[1], dwords[2], dwords[3], dwords[4],
                if (resolution[0] == 'g')
                    "the waiter's predicate data is the guest memory behind this object"
                else
                    "host-side primitive internals; the waiter's predicate lives inside the guest, not at this address",
            },
        );
    } else {
        machoCapturePrint(
            "  object memory not readable through the emulator's memory view (host=0x{x}); the waiter's predicate state is elsewhere — in the guest object's own fields, not in this runtime's copy of it\n",
            .{host},
        );
    }
    for (waiter_handles[0..waiter_count]) |handle| {
        machoCapturePrint(
            "  waiter thread=0x{x} parked_steps={d} first_wait_step={d}\n",
            .{ handle, parked_steps, first_wait_step },
        );
    }
}

pub fn stallReleaseProgress(self: anytype) u64 {
    return self.wait_audit.witness.get(.pipeline_stage) +
        self.wait_audit.witness.get(.ring_publication) +
        self.wait_audit.witness.get(.gpu_callback) +
        self.wait_audit.witness.get(.module_load) +
        self.wait_audit.witness.get(.presented_frame);
}

pub fn noteStallReleaseGranted(self: anytype, object: u64, thread: u64, waited_steps: u64) void {
    const progress = self.stallReleaseProgress();
    const decision = self.stall_release.authorise(
        object,
        1,
        0,
        waited_steps,
        notifier_liveness.default_stall_steps,
    );
    if (!decision.granted()) return;
    self.stall_release.noteReleased(object, 0, thread, progress, self.executed_steps);
    machoCapturePrint(
        "macho-processor: STALL RELEASE: recorded object=0x{x} thread=0x{x} waited_steps={d} progress_witness={d} step={d}; {s}\n",
        .{ object, thread, waited_steps, progress, self.executed_steps, decision.meaning() },
    );
}

pub fn logBringupFailures(self: anytype) void {
    const ledger = &self.bringup_failures;
    if (ledger.count == 0) return;
    // The same witness the wait audit classifies against, so the two can
    // never disagree about whether the run is moving.
    ledger.noteProgress(self.stallReleaseProgress(), self.executed_steps);
    const finding = ledger.finding(self.executed_steps);
    machoCapturePrint(
        "macho-processor: BRINGUP FAILURE: finding={s} failures={d} dropped={d} progress={d} last_progress_step={d} step={d}; {s}\n",
        .{
            finding.label(),
            ledger.count,
            ledger.dropped,
            ledger.progress,
            ledger.last_progress_step,
            self.executed_steps,
            ledger.verdict(self.executed_steps),
        },
    );
    for (ledger.failures[0..ledger.count]) |entry| {
        machoCapturePrint(
            "  subsystem {s: <24} {s: <10} step={d} thread_exited={s} reason='{s}'\n",
            .{
                entry.subsystem.label(),
                ledger.classify(entry, self.executed_steps).label(),
                entry.step,
                if (entry.thread_exited) "YES" else "NO",
                entry.reason(),
            },
        );
    }
    if (ledger.root(self.executed_steps)) |root| machoCapturePrint(
        "macho-processor: BRINGUP FAILURE: ROOT subsystem={s} step={d} — {s}\n",
        .{ root.subsystem.label(), root.step, root.subsystem.blocks() },
    );
}

pub fn logStallRelease(self: anytype) void {
    self.refreshStallRelease();
    const ledger = &self.stall_release;
    if (ledger.count == 0 and ledger.refusals == 0) return;
    machoCapturePrint(
        "macho-processor: STALL RELEASE: objects={d} attempts={d}/{d} decisive={d} refusals={d} last_refusal={s} step={d}; {s}\n",
        .{
            ledger.count,
            ledger.total_attempts,
            stall_release.max_attempts_total,
            ledger.decisiveCount(),
            ledger.refusals,
            if (ledger.last_refusal) |refusal| refusal.label() else "-",
            self.executed_steps,
            ledger.verdict(),
        },
    );
    for (ledger.attempts[0..ledger.count]) |attempt| {
        machoCapturePrint(
            "  release object=0x{x:0>8} thread=0x{x} attempts={d} {s: <22} progress={d}->{d} released_step={d}\n",
            .{
                attempt.object,
                attempt.thread,
                attempt.attempts,
                attempt.outcome.label(),
                attempt.progress_before,
                attempt.progress_after,
                attempt.released_step,
            },
        );
        if (attempt.outcome.decisive()) machoCapturePrint(
            "    verdict: {s}\n",
            .{attempt.outcome.meaning()},
        );
    }
}

pub fn preflightOutcomeStatus(
    outcome: preflight_lib.host_capability.Outcome,
) host_contract_coverage.Status {
    return switch (outcome) {
        .verified => .satisfied,
        .degraded => .degraded,
        .failed, .unavailable => .unsatisfied,
        .unprobed => .untested,
    };
}

pub fn preflightAddressTranslation() bool {
    const model_base: u64 = 0x1000_0000;
    var model: xenia_memory_views.Model = .{};
    if (model.observeFixedFileView(
        model_base,
        xenia_memory_views.primary_view_length,
        0,
        false,
    ) != .discovered) {
        return false;
    }
    if (!model.ready()) return false;

    const virtual_address = model.virtualHostAddress(0xFFCAB000) orelse return false;
    const unbiased_address = model.primaryUnbiasedHostAddress(0xFFCAB000) orelse return false;
    if (virtual_address -| unbiased_address != xenia_memory_views.physical_4k_bias) return false;

    const physical_address = xenia_memory_views.Model.physicalAddressForVirtual(0xFFCAB000) orelse return false;
    if (physical_address != 0x01FCAC000) return false;
    if (model.physicalHostAddress(physical_address) == null) return false;
    inline for ([_]xenia_memory_views.PhysicalProjection{
        .physical,
        .a_virtual,
        .c_virtual,
        .e_virtual,
    }) |projection| {
        if (model.physicalProjectionHostAddress(0x0510C040, projection) == null) return false;
    }
    return model.physicalProjectionHostAddress(0xFFF, .e_virtual) == null;
}
