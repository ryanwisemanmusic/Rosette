// Split implementation for MachOState; wrappers keep the public state API stable.
const process = @import("../process.zig");
const __ProcessInternals = process.__ProcessInternals;
const MachOState = process.MachOState;
const BOUND_IMPORT_THUNK_BASE = __ProcessInternals._BOUND_IMPORT_THUNK_BASE;
const BoundImportThunk = __ProcessInternals._BoundImportThunk;
const Op = __ProcessInternals._Op;
const abi_data_materializer = __ProcessInternals._abi_data_materializer;
const application_framework = __ProcessInternals._application_framework;
const applyBindingAddend = __ProcessInternals._applyBindingAddend;
const durable_journal = __ProcessInternals._durable_journal;
const dyld = __ProcessInternals._dyld;
const environmentFlag = __ProcessInternals._environmentFlag;
const environmentUnsigned = __ProcessInternals._environmentUnsigned;
const execution_history = __ProcessInternals._execution_history;
const execution_provenance = __ProcessInternals._execution_provenance;
const execution_tracepoints = __ProcessInternals._execution_tracepoints;
const fcntl_c = __ProcessInternals._fcntl_c;
const gpu = __ProcessInternals._gpu;
const import_handler = __ProcessInternals._import_handler;
const import_integrity = __ProcessInternals._import_integrity;
const libcpp_stream_bridge = __ProcessInternals._libcpp_stream_bridge;
const log = __ProcessInternals._log;
const macho = __ProcessInternals._macho;
const machoCapturePrint = __ProcessInternals._machoCapturePrint;
const macho_log = __ProcessInternals._macho_log;
const macho_metadata = __ProcessInternals._macho_metadata;
const main = __ProcessInternals._main;
const native_window = __ProcessInternals._native_window;
const pointer_firewall = __ProcessInternals._pointer_firewall;
const primitiveCapturePrint = __ProcessInternals._primitiveCapturePrint;
const run_closure = __ProcessInternals._run_closure;
const run_journal = __ProcessInternals._run_journal;
const run_manifest = __ProcessInternals._run_manifest;
const scheduler = __ProcessInternals._scheduler;
const setenv = __ProcessInternals._setenv;
const startup_observer = __ProcessInternals._startup_observer;
const std = __ProcessInternals._std;
const storage_integrity = __ProcessInternals._storage_integrity;
const vtt_resolution = __ProcessInternals._vtt_resolution;
const guestAlloc = __ProcessInternals._guestAlloc;
const guestMemory = __ProcessInternals._guestMemory;
const guestMemoryConst = __ProcessInternals._guestMemoryConst;
const read64 = __ProcessInternals._read64;
const registerSyntheticThunk = __ProcessInternals._registerSyntheticThunk;
const write64 = __ProcessInternals._write64;
const closeGuestFiles = MachOState.closeGuestFiles;
const init = MachOState.init;
const run = MachOState.run;
const standardStreamPointer = MachOState.standardStreamPointer;
const step = MachOState.step;

pub fn dumpPrimitiveTotals(self: anytype) void {
    const log_cb = import_handler.PrimitiveLogCallbacks{
        .ctx = @ptrCast(&self.macho_log),
        .logLine = struct {
            fn log(_: *anyopaque, text: []const u8) void {
                primitiveCapturePrint("{s}", .{text});
            }
        }.log,
    };
    self.import_handler.dumpTotals(log_cb);
}

pub fn runIdentity(self: anytype) run_closure.Identity {
    var identity = run_closure.Identity{};
    const fields = self.audit_identity_fields;
    const set = struct {
        fn call(identity_out: *run_closure.Identity, field: run_closure.IdentityField, value: u64) void {
            _ = identity_out.set(field, value);
        }
    }.call;
    set(&identity, .rosette_source_tree, fields.rosette_tree_hash);
    set(&identity, .rosette_generated_tree, fields.rosette_generated_tree_hash);
    set(&identity, .xenia_source_tree, fields.xenia_tree_hash);
    set(&identity, .xenia_fork_tree, fields.fork_manifest_hash);
    set(&identity, .xenia_base_commit, fields.xenia_base_commit_hash);
    set(&identity, .title_xex, self.audit_manifest.inputHash(.image));
    set(&identity, .title_xiso, self.audit_manifest.inputHash(.media));
    set(&identity, .media, self.audit_manifest.inputHash(.media));
    set(&identity, .compiler, fields.toolchain_hash);
    set(&identity, .linker, fields.toolchain_hash);
    set(&identity, .translator, fields.rosette_tree_hash);
    set(&identity, .generator, fields.generated_artifact_hash);
    set(&identity, .shell_helper, fields.helper_hash);
    set(&identity, .build_graph, fields.build_hash);
    set(&identity, .toolchain, fields.toolchain_hash);
    set(&identity, .backend, fields.backend_hash);
    set(&identity, .device, fields.device_hash);
    set(&identity, .driver, fields.driver_hash);
    set(&identity, .moltenvk, fields.moltenvk_hash);
    set(&identity, .metal, fields.metal_hash);
    set(&identity, .semantic_config, fields.semantic_config_hash);
    set(&identity, .time_config, fields.time_config_hash);
    set(&identity, .scheduler_config, fields.scheduler_config_hash);
    set(&identity, .observer_config, fields.observer_config_hash);
    set(&identity, .admission_config, fields.admission_config_hash);
    set(&identity, .budget_config, fields.budget_config_hash);
    set(&identity, .frontier_config, fields.frontier_config_hash);
    set(&identity, .shader_assets, fields.shader_assets_hash);
    set(&identity, .vendor_libraries, fields.vendor_hash);
    set(&identity, .test_manifest, fields.test_runner_hash);
    set(&identity, .shell_update, fields.shell_update_hash);
    return identity;
}

pub fn configureAdmission(self: anytype, manifest_sealed: bool) void {
    const closure_profile: run_closure.Profile = switch (self.audit_profile) {
        .authentic => .authentic,
        .diagnostic => .diagnostic,
        .synthetic => .synthetic,
        .replay => .replay,
    };
    self.audit_closure_admission = run_closure.Admission.init(
        self.audit_manifest.identity.run_id,
        closure_profile,
        self.runIdentity(),
    );
    self.audit_closure_admission_failure = if (!self.audit_profile_valid or
        self.audit_identity_conflict)
        .identity_incomplete
    else if (!manifest_sealed)
        .seal_missing
    else
        self.audit_closure_admission.seal();

    if (self.audit_profile != .authentic) {
        self.audit_guest_start_verdict =
            self.audit_closure_admission.requestGuestStart();
    } else if (self.audit_closure_admission_failure == .none) {
        self.audit_guest_start_verdict =
            self.audit_closure_admission.requestGuestStart();
    } else {
        self.audit_guest_start_verdict = .refused;
    }
}

pub fn auditEnvironmentMatches(self: anytype, name: [*:0]const u8, expected: u64) bool {
    _ = self;
    if (std.c.getenv(name) == null) return true;
    return run_manifest.hashFromEnvironment(name) == expected;
}

pub fn setAuditBackend(self: anytype, backend: []const u8) bool {
    if (backend.len == 0 or backend.len > self.audit_backend_name.len) return false;
    @memset(&self.audit_backend_name, 0);
    @memcpy(self.audit_backend_name[0..backend.len], backend);
    self.audit_backend_name_length = @intCast(backend.len);
    return true;
}

pub fn auditBackend(self: anytype) []const u8 {
    return self.audit_backend_name[0..self.audit_backend_name_length];
}

pub fn publishAuditEnvironment(self: anytype, allocator: std.mem.Allocator) bool {
    if (!self.audit_manifest.sealIntact()) return false;

    const manifest_hash = self.audit_manifest.fingerprint();
    const run_matches = self.auditEnvironmentMatches("ROSETTE_RUN_ID", self.audit_manifest.identity.run_id);
    const manifest_matches = self.auditEnvironmentMatches("ROSETTE_MANIFEST_HASH", manifest_hash);
    const build_identity_matches = self.audit_build_identity_hash == 0 or
        self.auditEnvironmentMatches("ROSETTE_BUILD_IDENTITY_HASH", self.audit_build_identity_hash);
    if (!run_matches or !manifest_matches or !build_identity_matches) {
        machoCapturePrint(
            "macho-processor: AUDIT IDENTITY: refusing publication; pre-existing environment agrees run={} manifest={} build_identity={}\n",
            .{ run_matches, manifest_matches, build_identity_matches },
        );
        return false;
    }

    var buffer: [32]u8 = undefined;
    const publish = struct {
        fn value(allocator_out: std.mem.Allocator, name: [*:0]const u8, number: u64, buffer_out: []u8) bool {
            // A zero is not a value the reader can accept: the emulator's
            // run context rejects a zero hash as absent, so publishing one
            // would produce a refusal on the far side of the handshake
            // rather than here, where the cause is. Refuse it locally and
            // let the admission line name it.
            if (number == 0) return false;
            const text = std.fmt.bufPrint(buffer_out, "0x{x}", .{number}) catch return false;
            const text_z = allocator_out.dupeZ(u8, text) catch return false;
            return setenv(name, text_z.ptr, 1) == 0;
        }
    }.value;
    const publishText = struct {
        fn value(allocator_out: std.mem.Allocator, name: [*:0]const u8, text: []const u8) bool {
            if (text.len == 0) return false;
            const text_z = allocator_out.dupeZ(u8, text) catch return false;
            return setenv(name, text_z.ptr, 1) == 0;
        }
    }.value;
    if (!publish(allocator, "ROSETTE_RUN_ID", self.audit_manifest.identity.run_id, &buffer)) {
        machoCapturePrint("macho-processor: AUDIT IDENTITY: publication failed field=ROSETTE_RUN_ID\n", .{});
        return false;
    }
    if (!publish(allocator, "ROSETTE_MANIFEST_HASH", manifest_hash, &buffer)) {
        machoCapturePrint("macho-processor: AUDIT IDENTITY: publication failed field=ROSETTE_MANIFEST_HASH\n", .{});
        return false;
    }
    if (self.audit_build_identity_hash != 0 and
        !publish(allocator, "ROSETTE_BUILD_IDENTITY_HASH", self.audit_build_identity_hash, &buffer))
    {
        machoCapturePrint("macho-processor: AUDIT IDENTITY: publication failed field=ROSETTE_BUILD_IDENTITY_HASH\n", .{});
        return false;
    }
    if (!publishText(allocator, "ROSETTE_BACKEND", self.auditBackend())) {
        machoCapturePrint("macho-processor: AUDIT IDENTITY: publication failed field=ROSETTE_BACKEND\n", .{});
        return false;
    }
    // Read back through the same call the guest's own lookup will make.
    //
    // A publish that reports success and a variable that cannot be read
    // afterwards are indistinguishable from here, and that difference was
    // worth several hours: the guest refused its own start over an absent
    // identity while this step believed it had handed one over.
    const run_readback = run_manifest.hashFromEnvironment("ROSETTE_RUN_ID");
    const manifest_readback = run_manifest.hashFromEnvironment("ROSETTE_MANIFEST_HASH");
    const build_identity_readback = if (self.audit_build_identity_hash != 0)
        run_manifest.hashFromEnvironment("ROSETTE_BUILD_IDENTITY_HASH")
    else
        0;
    const backend_readback = if (std.c.getenv("ROSETTE_BACKEND")) |raw|
        std.mem.eql(u8, std.mem.span(raw), self.auditBackend())
    else
        false;
    const agrees = run_readback == self.audit_manifest.identity.run_id and
        manifest_readback == manifest_hash and
        (self.audit_build_identity_hash == 0 or
            build_identity_readback == self.audit_build_identity_hash) and
        backend_readback;
    machoCapturePrint(
        "macho-processor: AUDIT IDENTITY: published run=0x{x} manifest=0x{x} build_identity=0x{x} backend={s}; readback run=0x{x} manifest=0x{x} build_identity=0x{x} backend_agrees={} agrees={}\n",
        .{
            self.audit_manifest.identity.run_id,
            manifest_hash,
            self.audit_build_identity_hash,
            self.auditBackend(),
            run_readback,
            manifest_readback,
            build_identity_readback,
            backend_readback,
            agrees,
        },
    );
    return agrees;
}

pub fn configureAuditContracts(self: anytype, at_step: u64) void {
    if (self.audit_configured) return;
    self.audit_configured = true;

    const run_id = if (self.event_stream.run_id == 0) 1 else self.event_stream.run_id;
    self.audit_manifest.identity = .{
        .run_id = run_id,
        .image_hash = self.audit_image_fingerprint,
        .media_hash = self.audit_media_fingerprint,
        .title_id = self.audit_title_id,
    };
    _ = self.audit_manifest.declareInput(.image, self.audit_image_fingerprint);
    _ = self.audit_manifest.declareInput(.media, self.audit_media_fingerprint);
    _ = self.audit_manifest.declareInput(.config, self.audit_config_fingerprint);
    _ = self.audit_manifest.setIdentityFields(
        run_manifest.identityFieldsWithImage(
            self.audit_identity_fields,
            self.audit_image_fingerprint,
            self.entry_point_vaddr,
        ),
    );
    _ = self.audit_manifest.setBudget(.{
        .guest_ms_per_host_second = environmentUnsigned("ROSETTE_GUEST_MS_PER_HOST_SECOND", 0),
        .window_host_seconds = environmentUnsigned("ROSETTE_RUN_WINDOW_SECONDS", 0),
        .guest_ms_target = environmentUnsigned("ROSETTE_GUEST_MS_TARGET", 0),
    });
    self.audit_manifest.profile = self.audit_profile;
    inline for ([_]run_manifest.Feature{
        .ring_transport,
        .pm4_decode,
        .render_target,
        .edram,
        .resolve,
        .synchronization,
        .interrupt_effect,
        .frame_custody,
        .execution_provenance,
        .memory_alias,
        .storage_integrity,
        .translation_budget,
        .vulkan_forwarding,
        .kernel_service,
        .import_integrity,
        .shader_pipeline,
    }) |feature| {
        _ = self.audit_manifest.declareFeature(feature);
    }

    const admission_profile: gpu.feature_admission.Profile = switch (self.audit_profile) {
        .authentic => .authentic,
        .diagnostic => .diagnostic,
        .synthetic => .synthetic,
        .replay => .replay,
    };
    _ = self.audit_admission.declare(admission_profile);
    if (self.application_framework.xeniaHostGpuCallbackEnabled()) {
        _ = self.audit_admission.enable(
            .host_callback_forcing,
            "Rosette application-framework provider installed a Xenia host GPU callback",
        );
    }
    if (self.never_notified_repair_enabled) {
        _ = self.audit_admission.enable(
            .guest_memory_repair,
            "never-notified wait repair is enabled",
        );
    }
    if (self.gpu_draw_dispatch.policy != .observe_only) {
        _ = self.audit_admission.enable(
            .host_signal_forcing,
            "draw dispatch policy can deliver a modeled completion signal",
        );
    }
    if (environmentFlag("ROSETTE_MACHO_FORCE_GPU") or
        environmentFlag("ROSETTE_MACHO_FORCE_RING") or
        environmentFlag("ROSETTE_MACHO_FORCE_SWAP"))
    {
        _ = self.audit_admission.enable(
            .ring_write_pointer_kick,
            "a ROSETTE force control can mutate the GPU publication path",
        );
    }
    self.audit_admission.sealConfiguration();

    const manifest_sealed = self.audit_profile_valid and self.audit_manifest.seal();
    self.configureAdmission(manifest_sealed);
    machoCapturePrint(
        "macho-processor: AUDIT MANIFEST: run=0x{x} image=0x{x} media=0x{x} config=0x{x} profile={s} profile_valid={} sealed={} identity_complete={} closure_admission={s} closure_failure={s} start={s} admission={s} admission_fingerprint=0x{x}\n",
        .{
            run_id,
            self.audit_image_fingerprint,
            self.audit_media_fingerprint,
            self.audit_config_fingerprint,
            self.audit_profile.label(),
            self.audit_profile_valid,
            manifest_sealed,
            self.audit_manifest.identity_fields.complete(),
            self.audit_guest_start_verdict.label(),
            self.audit_closure_admission_failure.label(),
            self.audit_guest_start_verdict.label(),
            self.audit_admission.admission().label(),
            self.audit_admission.fingerprint(),
        },
    );
    self.audit_journal.open(run_id);
    self.openAuditDurableJournal();
    if (self.audit_journal.written == 0) {
        _ = self.writeAuditJournal(.{
            .kind = @intFromEnum(run_journal.EventKind.run_started),
            .domain = @intFromEnum(run_journal.Domain.rosette_run_integrity),
            .source_class = @intFromEnum(run_journal.SourceClass.host_forwarded),
            .result_class = @intFromEnum(run_journal.ResultClass.observed),
            .guest_step = at_step,
        });
    }
    _ = self.writeAuditJournal(.{
        .kind = @intFromEnum(run_journal.EventKind.run_manifest),
        .domain = @intFromEnum(run_journal.Domain.rosette_run_integrity),
        .source_class = @intFromEnum(run_journal.SourceClass.host_forwarded),
        .result_class = @intFromEnum(run_journal.ResultClass.applied),
        .guest_step = at_step,
        .subject_id = self.audit_manifest.identity.image_hash,
        .generation = self.audit_manifest.features.count(),
        .actual_value = self.audit_manifest.features.bits,
        .state_hash = self.audit_manifest.fingerprint(),
        .effect_hash = self.audit_admission.fingerprint(),
    });
}

pub fn writeAuditJournal(self: anytype, record: run_journal.Record) bool {
    const result = self.audit_journal.writeAndTake(record);
    if (result.stamped) |stamped| {
        if (self.audit_evidence_owner_started and
            !self.audit_evidence_owner.acceptRecord(self.audit_evidence_owner_producer))
        {
            self.audit_durable_open_failed = true;
        }
        if (self.audit_durable_journal.started) {
            if (self.audit_durable_journal.append(stamped) != .accepted) {
                self.audit_durable_open_failed = true;
                if (self.audit_evidence_owner_started) self.audit_evidence_owner.noteWriterError();
            }
        }
    }
    return result.accepted;
}

pub fn writeCompactedAuditJournal(self: anytype, record: run_journal.Record) bool {
    const result = self.audit_journal.writeCompactedAndTake(record);
    if (result.stamped) |stamped| {
        if (self.audit_evidence_owner_started and
            !self.audit_evidence_owner.acceptRecord(self.audit_evidence_owner_producer))
        {
            self.audit_durable_open_failed = true;
        }
        if (self.audit_durable_journal.started) {
            if (self.audit_durable_journal.append(stamped) != .accepted) {
                self.audit_durable_open_failed = true;
                if (self.audit_evidence_owner_started) self.audit_evidence_owner.noteWriterError();
            }
        }
    }
    return result.accepted;
}

pub fn openAuditDurableJournal(self: anytype) void {
    if (self.audit_durable_journal.started or self.audit_durable_open_failed) return;
    const override = std.c.getenv("ROSETTE_DURABLE_JOURNAL");
    const path = if (override) |raw|
        self.allocator.dupe(u8, std.mem.span(raw)) catch return
    else blk: {
        const root = blk2: {
            const names = [_][*:0]const u8{
                "ROSETTE_TRACE_ROOT",
                "ROSETTE_ROUTE_ROOT",
                "ROSETTE_CALLER_CWD",
                "PWD",
            };
            for (names) |name| {
                if (std.c.getenv(name)) |raw| {
                    const value = std.mem.span(raw);
                    if (value.len != 0) break :blk2 value;
                }
            }
            break :blk2 ".";
        };
        // A default run gets its own artifact directory and filename. The
        // run id is part of the name, and O_EXCL below makes even an
        // accidental reuse fail rather than truncating a prior run.
        const filename = std.fmt.allocPrint(self.allocator, "run-{x:0>16}.r3j", .{self.audit_manifest.identity.run_id}) catch return;
        defer self.allocator.free(filename);
        break :blk self.allocator.dupe(u8, std.fs.path.join(self.allocator, &.{ root, ".rosette", "runs", filename }) catch return) catch return;
    };
    defer self.allocator.free(path);
    const path_z = self.allocator.dupeZ(u8, path) catch return;
    defer self.allocator.free(path_z);
    const directory = std.fs.path.dirname(path);
    if (directory) |parent| {
        // The event logger creates the default .rosette directory. A
        // custom path is allowed as well; failure to create its parent is
        // reported by the writer as an unavailable durability channel.
        std.Io.Dir.cwd().createDirPath(self.io, parent) catch {};
    }
    const fd = fcntl_c.open(
        path_z.ptr,
        // Never truncate or append to an older run. A collision is a
        // typed durability failure and keeps the new run diagnostic-only.
        fcntl_c.O_WRONLY | fcntl_c.O_CREAT | fcntl_c.O_EXCL | fcntl_c.O_CLOEXEC,
        @as(c_uint, 0o644),
    );
    if (fd < 0) {
        self.audit_durable_open_failed = true;
        machoCapturePrint("macho-processor: AUDIT JOURNAL: durable sink unavailable path={s}; the in-memory journal remains diagnostic-only\n", .{path});
        return;
    }
    const header = durable_journal.Header{
        .run_id = self.audit_manifest.identity.run_id,
        .manifest_hash = self.audit_manifest.fingerprint(),
        .schema_hash = self.audit_manifest.identity_fields.fingerprint(),
        .profile = @intFromEnum(self.audit_profile),
        .source_policy = @intFromEnum(if (self.audit_manifest.sealIntact())
            self.audit_manifest.effectiveSourceClass(self.audit_admission.effectiveSourceClass())
        else
            run_manifest.SourceClass.unknown),
        .host_monotonic_ns = startup_observer.monotonicNanoseconds(),
    };
    if (!self.audit_durable_journal.begin(fd, header)) {
        _ = std.c.close(fd);
        self.audit_durable_open_failed = true;
        return;
    }
    self.audit_durable_fd = fd;
    self.audit_evidence_owner_started =
        self.audit_evidence_owner.begin(self.audit_manifest.identity.run_id, true) and
        self.audit_evidence_owner.registerProducer(self.audit_evidence_owner_producer);
    machoCapturePrint(
        "macho-processor: AUDIT JOURNAL: durable sink path={s} schema={d} manifest=0x{x} profile={s} unique=YES owner={} footer_required=YES\n",
        .{ path, durable_journal.schema_version, header.manifest_hash, self.audit_profile.label(), self.audit_evidence_owner_started },
    );
}

pub fn finishAuditDurableJournal(self: anytype) void {
    if (self.audit_evidence_owner_started) {
        _ = self.audit_evidence_owner.unregisterProducer(self.audit_evidence_owner_producer);
        self.audit_evidence_owner_started = false;
        _ = self.audit_evidence_owner.beginDrain();
    }
    if (self.audit_durable_journal.started and !self.audit_durable_journal.finished) {
        const finished = self.audit_durable_journal.finish(self.audit_journal.summary().totalDropped());
        if (!finished) self.audit_evidence_owner.noteWriterError();
        const recovery = self.audit_durable_journal.recovery();
        _ = self.audit_evidence_owner.noteFooter(recovery.footer_valid);
        _ = self.audit_evidence_owner.noteDurableFooter(recovery.durable_footer);
        if (self.audit_journal.summary().totalDropped() != 0) {
            self.audit_evidence_owner.noteDrop(self.audit_journal.summary().totalDropped());
        }
        _ = self.audit_evidence_owner.commit();
    }
    if (self.audit_durable_fd >= 0) {
        _ = std.c.close(self.audit_durable_fd);
        self.audit_durable_fd = -1;
    }
}

pub fn deinit(self: anytype) void {
    self.finishAuditDurableJournal();
    self.execution_history.deinit(self.allocator);
    self.scheduler_log.close();
    self.jit_log.close();
    self.macho_log.close();
    self.guest_time.deinit(self.allocator);
    self.closeGuestFiles();
    self.libcxx_streams.deinit();
    self.dumpPrimitiveTotals();
    self.local_libcpp_stream_targets.deinit();
    self.import_handler.deinit();
    self.vtable_tracker.deinit();
    self.vtable_stack_registry.deinit();
    self.guard_rollback.deinit();
    self.import_resolver.deinit();
    self.initializer_resolver.deinit();
    self.vtt_resolver.deinit();
    self.dynamic_forwarder.deinit();
    self.native_window.deinit();
    self.fs_forwarder.deinit();
    self.memory_forwarder.deinit();
    self.sparse_memory.deinit();
    self.memory_regions.deinit();
    self.memory_writes.deinit(self.allocator);
    self.pointer_firewall.deinit();
    if (self.symbol_assembly_catalog) |*catalog| catalog.deinit();
    self.symbol_assembly.deinit();
    self.allocator.free(self.page_permissions);
    if (self.gpu_xenos_resolve_scratch.len != 0) self.allocator.free(self.gpu_xenos_resolve_scratch);
    if (self.gpu_xenos_edram.len != 0) self.allocator.free(self.gpu_xenos_edram);
    self.initializer_memory.deinit();
    self.allocator.free(self.decode_cache);
    self.allocator.free(self.decode_victim_cache);
    self.allocator.free(self.static_decode_l2);
    self.allocator.destroy(self.decode_cache_pages);
    if (self.special_rip_table.len != 0) self.allocator.free(self.special_rip_table);
    if (self.guest_log_mirror_fd >= 0) _ = std.c.close(self.guest_log_mirror_fd);
    self.metadata.deinit();
    self.allocator.free(self.mem);
    self.allocator.free(self.segments);
    if (self.bound_import_thunks.len != 0) self.allocator.free(self.bound_import_thunks);

    // Shutdown the thread scheduler
    // self.thread_scheduler.shutdown();
}

pub fn scheduleGuestWaitDeadline(
    self: anytype,
    thread: u64,
    wait_object: u64,
    wait_generation: u64,
    deadline_ns: u64,
) u64 {
    return self.guest_time.schedule(self.allocator, deadline_ns, thread, wait_object, wait_generation) catch {
        self.scheduler_log.emit(.{
            .kind = .deadlock,
            .step = self.executed_steps,
            .thread = thread,
            .object = wait_object,
            .generation = wait_generation,
            .deadline_ns = deadline_ns,
            .reason = "deadline_registration_failed",
        });
        return 0;
    };
}

pub fn applyDyldBindings(self: anytype) !void {
    var stubs = std.StringHashMap(u64).init(self.allocator);
    defer stubs.deinit();
    for (self.metadata.imports) |imported| {
        try stubs.put(imported.name, imported.stub_address);
    }

    var thunk_addresses = std.StringHashMap(u64).init(self.allocator);
    defer thunk_addresses.deinit();
    var thunks: std.ArrayList(BoundImportThunk) = .empty;
    errdefer thunks.deinit(self.allocator);

    var applied: usize = 0;
    var callable_got_bindings: usize = 0;
    var writable_callable_bindings: usize = 0;
    var capstone_callback_bindings: usize = 0;
    var bridged_abi_data_bindings: usize = 0;
    var deferred_abi_data_bindings: usize = 0;
    var standard_stream_bindings: usize = 0;
    var local_image_data_bindings: usize = 0;
    var preserved_weak_data_bindings: usize = 0;
    var stack_guard_address: u64 = 0;
    for (self.metadata.bindings) |binding| {
        if (std.mem.eql(u8, binding.name, "___stdinp") or
            std.mem.eql(u8, binding.name, "___stdoutp") or
            std.mem.eql(u8, binding.name, "___stderrp"))
        {
            const pointer_address = self.standardStreamPointer(binding.name) orelse continue;
            if (self.guestMemory(binding.address, @sizeOf(u64)) == null) continue;
            self.write64(binding.address, pointer_address);
            applied += 1;
            continue;
        }
        if (std.mem.eql(u8, binding.name, "___stack_chk_guard")) {
            if (stack_guard_address == 0) {
                stack_guard_address = self.guestAlloc(@sizeOf(u64), @alignOf(u64)) orelse continue;
                self.write64(stack_guard_address, 0x9E37_79B9_7F4A_7C15);
            }
            if (self.guestMemory(binding.address, @sizeOf(u64)) == null) continue;
            self.write64(binding.address, stack_guard_address);
            applied += 1;
            continue;
        }
        if (standardCppStreamKind(binding.name)) |kind| {
            // std::cin/cout/cerr/clog are data symbols exported from
            // libc++. A plain dyld binding would have fallen through the
            // callable/ABI-data checks and left the slot zeroed, so
            // `std::cerr << ...` handed a null ostream to native libc++
            // code (the Xbyak near-null casualty). Bind the slot to a
            // fully modeled synthetic stream instead: every stream
            // operator that reaches native libc++ runs against valid
            // state, and every import the bridge intercepts dispatches
            // against the same object.
            const ostream = self.libcxx_streams.ensureStandardStream(self, kind) orelse {
                machoCapturePrint(
                    "macho-processor: standard C++ stream construction failed for {s}\n",
                    .{binding.name},
                );
                continue;
            };
            if (self.guestMemory(binding.address, @sizeOf(u64)) == null) continue;
            self.write64(binding.address, ostream);
            applied += 1;
            standard_stream_bindings += 1;
            continue;
        }
        const section = self.metadata.sectionAtAddress(binding.address) orelse continue;
        if (isLocalBindingScope(binding.dylib)) {
            if (self.metadata.definedSymbolAddress(binding.name)) |defined_address| {
                const target = applyBindingAddend(defined_address, binding.addend) orelse {
                    machoCapturePrint(
                        "macho-processor: rejected overflowing local-image binding addend: slot=0x{x} symbol={s} target=0x{x} addend={d}\n",
                        .{ binding.address, binding.name, defined_address, binding.addend },
                    );
                    continue;
                };
                const destination = self.guestMemory(binding.address, @sizeOf(u64)) orelse continue;
                std.mem.writeInt(u64, destination[0..8], target, .little);
                if (std.mem.eql(u8, section.name, "__got")) {
                    _ = self.memory_regions.register(binding.address, @sizeOf(u64), .{ .read = true, .write = true }, .import_got, binding.name, self.regs.rip);
                }
                applied += 1;
                local_image_data_bindings += 1;
                continue;
            }
        }
        if (std.mem.eql(u8, binding.dylib, "weak-lookup") and binding.addend == 0) {
            const destination = self.guestMemoryConst(binding.address, @sizeOf(u64)) orelse continue;
            const existing = std.mem.readInt(u64, destination[0..8], .little);
            if (existing != 0 and self.metadata.sectionAtAddress(existing) != null) {
                applied += 1;
                preserved_weak_data_bindings += 1;
                continue;
            }
        }
        if (!isCallableConstantBinding(section, binding.name, stubs.contains(binding.name))) {
            if (isAbiDataSymbol(binding.name)) {
                if (isBridgedLibcppDataSymbol(binding.name)) {
                    bridged_abi_data_bindings += 1;
                } else {
                    deferred_abi_data_bindings += 1;
                    self.vtt_resolver.record(binding.address, binding.name, binding.addend) catch {};
                }
            }
            continue;
        }
        const destination = self.guestMemory(binding.address, @sizeOf(u64)) orelse continue;
        const existing = std.mem.readInt(u64, destination[0..8], .little);
        if (std.mem.eql(u8, binding.dylib, "weak-lookup") and existing != 0) continue;
        const capstone_callback_slot = self.capstoneCallbackSlotName(binding.address);
        // Function pointers stored in writable runtime data don't pass
        // through a normal call-site lazy-binding sequence. Route them
        // through Rosette's direct bound thunks so callbacks such as
        // Capstone's allocator hooks deterministically enter the import
        // dispatcher with the original ABI arguments intact.
        const force_bound_thunk = bindingRequiresBoundThunk(section, capstone_callback_slot != null);
        var target = if (!force_bound_thunk) stubs.get(binding.name) orelse 0 else 0;
        if (target == 0) target = blk: {
            if (thunk_addresses.get(binding.name)) |existing_thunk| break :blk existing_thunk;
            const thunk_address = BOUND_IMPORT_THUNK_BASE + @as(u64, @intCast(thunks.items.len)) * self.metadata.importThunkStride();
            try thunks.append(self.allocator, .{
                .address = thunk_address,
                .name = binding.name,
                .dylib = binding.dylib,
            });
            try thunk_addresses.put(binding.name, thunk_address);
            break :blk thunk_address;
        };
        if (target < BOUND_IMPORT_THUNK_BASE) {
            target = applyBindingAddend(target, binding.addend) orelse {
                machoCapturePrint(
                    "macho-processor: rejected overflowing dyld binding addend: slot=0x{x} symbol={s} target=0x{x} addend={d}\n",
                    .{ binding.address, binding.name, target, binding.addend },
                );
                continue;
            };
        }
        std.mem.writeInt(u64, destination[0..8], target, .little);
        _ = self.memory_regions.register(binding.address, @sizeOf(u64), .{ .read = true, .write = true }, .import_got, binding.name, self.regs.rip);
        applied += 1;
        if (std.mem.eql(u8, section.name, "__got")) callable_got_bindings += 1;
        if (isWritableDataSection(section)) writable_callable_bindings += 1;
        if (capstone_callback_slot) |slot_name| {
            capstone_callback_bindings += 1;
            machoCapturePrint(
                "macho-processor: Capstone runtime callback binding: slot={s} address=0x{x} import={s} target=0x{x} section={s} route=direct_bound_thunk repaired_null={}\n",
                .{ slot_name, binding.address, binding.name, target, section.name, existing == 0 },
            );
        }
    }

    self.bound_import_thunks = try thunks.toOwnedSlice(self.allocator);
    for (self.bound_import_thunks) |thunk| {
        self.registerSyntheticThunk(thunk.address, self.metadata.importThunkStride(), thunk.name);
    }

    if (self.vtt_resolver.totalDeferred() > 0) {
        const resolved = blk: {
            var count: usize = 0;
            var synthetic_count: usize = 0;
            var sentinel_count: usize = 0;
            var sentinel_samples: usize = 0;
            var category_counts = [_]usize{0} ** std.enums.values(abi_data_materializer.Category).len;
            var synthetic_symbols = std.StringHashMap(u64).init(self.allocator);
            defer synthetic_symbols.deinit();
            for (self.vtt_resolver.deferred.items) |*item| {
                if (item.resolution != .pending) continue;
                const category = abi_data_materializer.classify(item.symbol);
                if (category != .unknown) {
                    const base = synthetic_symbols.get(item.symbol) orelse materialized: {
                        const result = abi_data_materializer.materialize(self, item.symbol) orelse break :materialized 0;
                        synthetic_symbols.put(item.symbol, result.address) catch break :materialized 0;
                        category_counts[@intFromEnum(result.category)] += 1;
                        break :materialized result.address;
                    };
                    const value = if (base != 0) applyBindingAddend(base, item.addend) else null;
                    if (value) |target| {
                        self.write64(item.address, target);
                        item.resolution = .synthetic_abi;
                        synthetic_count += 1;
                        continue;
                    }
                }
                if (vtt_resolution.VttBindingResolver.lookupSymbol(item.symbol)) |base| {
                    const value = applyBindingAddend(base, item.addend) orelse base;
                    self.write64(item.address, value);
                    item.resolution = .host_symbol;
                    count += 1;
                } else {
                    self.write64(item.address, item.address);
                    item.resolution = .self_sentinel;
                    sentinel_count += 1;
                    if (sentinel_samples < 8) {
                        machoCapturePrint(
                            "macho-processor: unresolved ABI data fallback sample: address=0x{x} symbol={s} action=self_sentinel host_lookup=missing\n",
                            .{ item.address, item.symbol },
                        );
                        sentinel_samples += 1;
                    }
                }
            }
            if (synthetic_count > 0) {
                machoCapturePrint(
                    "macho-processor: guest ABI data materialized: bindings={d} unique(typeinfo/type_name/vtable/construction_vtable/vtt/guard/reference_temporary)={d}/{d}/{d}/{d}/{d}/{d}/{d}; relocation addends preserved\n",
                    .{ synthetic_count, category_counts[@intFromEnum(abi_data_materializer.Category.typeinfo)], category_counts[@intFromEnum(abi_data_materializer.Category.type_name)], category_counts[@intFromEnum(abi_data_materializer.Category.vtable)], category_counts[@intFromEnum(abi_data_materializer.Category.construction_vtable)], category_counts[@intFromEnum(abi_data_materializer.Category.vtt)], category_counts[@intFromEnum(abi_data_materializer.Category.guard)], category_counts[@intFromEnum(abi_data_materializer.Category.reference_temporary)] },
                );
            }
            if (sentinel_count > 0) {
                machoCapturePrint(
                    "macho-processor: unresolved ABI data fallback summary: total={d} samples={d} suppressed={d} action=self_sentinel compatibility_only=true\n",
                    .{ sentinel_count, sentinel_samples, sentinel_count - sentinel_samples },
                );
            }
            self.vtt_resolver.resolved_count = count;
            self.vtt_resolver.synthetic_count = synthetic_count;
            self.vtt_resolver.failed_count = sentinel_count;
            break :blk count;
        };
        if (self.vtt_resolver.synthetic_count > 0) {
            applied +|= self.vtt_resolver.synthetic_count;
        }
        if (resolved > 0) {
            applied +|= resolved;
            machoCapturePrint(
                "macho-processor: resolved {d} deferred ABI data binding(s) via host symbol lookup\n",
                .{resolved},
            );
        }
    }

    machoCapturePrint(
        "macho-processor: applied {d} dyld data binding(s), including {d} local-image pointer(s), {d} validated prebound weak pointer(s), {d} callable GOT pointer(s), {d} writable function pointer(s), and {d}/5 Capstone runtime callback(s); created {d} synthetic import thunk(s); ABI data bridged={d} deferred={d} guest_materialized={d} host_resolved={d} standard_cpp_streams={d}\n",
        .{ applied, local_image_data_bindings, preserved_weak_data_bindings, callable_got_bindings, writable_callable_bindings, capstone_callback_bindings, self.bound_import_thunks.len, bridged_abi_data_bindings, deferred_abi_data_bindings, self.vtt_resolver.synthetic_count, self.vtt_resolver.resolved_count, standard_stream_bindings },
    );
}

pub fn isLocalBindingScope(dylib: []const u8) bool {
    return std.mem.eql(u8, dylib, "self") or
        std.mem.eql(u8, dylib, "main-executable") or
        std.mem.eql(u8, dylib, "weak-lookup");
}

pub fn isCallableConstantBinding(
    section: macho_metadata.Section,
    symbol_name: []const u8,
    has_import_stub: bool,
) bool {
    // A dyld pointer binding for a symbol that also has an import stub is
    // a function pointer regardless of whether the compiler placed the
    // slot in __got, __const or writable __data. Capstone's cs_mem_* slots
    // are the important writable case: leaving them zero makes cs_open
    // return CS_ERR_MEMSETUP (8).
    if (has_import_stub) return true;
    if (std.mem.eql(u8, section.name, "__got")) return has_import_stub;
    if (!std.mem.eql(u8, section.name, "__const")) return false;
    if (!std.mem.startsWith(u8, symbol_name, "__Z")) return false;

    if (isAbiDataSymbol(symbol_name)) return false;
    return true;
}

pub fn isWritableDataSection(section: macho_metadata.Section) bool {
    return std.mem.eql(u8, section.segment_name, "__DATA") and
        !std.mem.eql(u8, section.name, "__got");
}

pub fn capstoneCallbackSlotName(self: anytype, address: u64) ?[]const u8 {
    const slots = [_][]const u8{
        "_cs_mem_malloc",
        "_cs_mem_calloc",
        "_cs_mem_realloc",
        "_cs_mem_free",
        "_cs_vsnprintf",
    };
    for (slots) |slot| {
        if (self.metadata.definedSymbolAddress(slot) == address) return slot;
    }
    return null;
}

pub fn dumpCoopBootstrapTrace(self: anytype) void {
    if (!self.coop_bootstrap_active or self.coop_bootstrap_index == 0) return;
    machoCapturePrint(
        "macho-processor: GTK worker bootstrap trace (incomplete, {d}/{d} entries):\n",
        .{ self.coop_bootstrap_index, 24 },
    );
    for (0..self.coop_bootstrap_index) |i| {
        const e = &self.coop_bootstrap_entries[i];
        const symbol = self.metadata.nearestSymbol(e.rip);
        const op_str = @tagName(@as(Op, @enumFromInt(e.op)));
        machoCapturePrint(
            "  [{d}] active=0x{x} rip=0x{x} {s}+0x{x} op={s} len={d}\n",
            .{
                i,                                           e.thread,                        e.rip,
                self.metadata.symbolLabelFor(symbol, e.rip), if (symbol) |s| s.offset else 0, op_str,
                e.len,
            },
        );
    }
}

pub fn dumpMemInitTrace(self: anytype) void {
    if (!self.mem_init_filled and self.mem_init_index == 0) return;
    const count: usize = if (self.mem_init_filled) 8 else self.mem_init_index;
    const start: usize = if (self.mem_init_filled) self.mem_init_index else 0;
    machoCapturePrint(
        "macho-processor: memory initialization progress (most recent {d} entries):\n",
        .{count},
    );
    for (0..count) |i| {
        const idx = (start + i) % 8;
        const e = &self.mem_init_entries[idx];
        const symbol = self.metadata.nearestSymbol(e.rip);
        machoCapturePrint(
            "  [{d}] step={d} rip=0x{x} {s}+0x{x} heap=0x{x} sparse(mappings/activations)={d}/{d} deferred={d} suspended={d}\n",
            .{
                i,                                           e.step,                          e.rip,
                self.metadata.symbolLabelFor(symbol, e.rip), if (symbol) |s| s.offset else 0, e.heap,
                e.sparse_mappings,                           e.sparse_activations,            e.deferred_count,
                e.suspended_count,
            },
        );
    }
}

pub fn dumpCapstoneCallbackState(self: anytype, reason: []const u8) void {
    const slots = [_][]const u8{
        "_cs_mem_malloc",
        "_cs_mem_calloc",
        "_cs_mem_realloc",
        "_cs_mem_free",
        "_cs_vsnprintf",
    };
    var present: usize = 0;
    var nonzero: usize = 0;
    machoCapturePrint("  Capstone runtime callback state ({s}):\n", .{reason});
    for (slots) |slot| {
        const address = self.metadata.definedSymbolAddress(slot) orelse {
            machoCapturePrint("    {s}: symbol_missing\n", .{slot});
            continue;
        };
        present += 1;
        const target = self.read64(address);
        if (target != 0) nonzero += 1;
        if (self.metadata.importAtStub(target)) |imported| {
            machoCapturePrint("    {s}: address=0x{x} target=0x{x} import={s}@{s}\n", .{ slot, address, target, imported.name, imported.dylib });
        } else if (self.metadata.nearestSymbol(target)) |symbol| {
            machoCapturePrint("    {s}: address=0x{x} target=0x{x} symbol={s}+0x{x}\n", .{ slot, address, target, symbol.name, symbol.offset });
        } else {
            machoCapturePrint("    {s}: address=0x{x} target=0x{x} unresolved={}\n", .{ slot, address, target, target != 0 });
        }
    }
    machoCapturePrint("    summary: symbols={d}/5 nonzero={d}/5 cs_open_requires_all_nonzero=true\n", .{ present, nonzero });
}

pub fn isAbiDataSymbol(symbol_name: []const u8) bool {
    const prefixes = [_][]const u8{ "__ZGV", "__ZGR", "__ZTC", "__ZTI", "__ZTS", "__ZTT", "__ZTV" };
    for (prefixes) |prefix| {
        if (std.mem.startsWith(u8, symbol_name, prefix)) return true;
    }
    return false;
}

pub fn standardCppStreamKind(symbol_name: []const u8) ?libcpp_stream_bridge.StandardStreamKind {
    if (std.mem.eql(u8, symbol_name, "__ZNSt3__14cinE")) return .cin;
    if (std.mem.eql(u8, symbol_name, "__ZNSt3__14coutE")) return .cout;
    if (std.mem.eql(u8, symbol_name, "__ZNSt3__14cerrE")) return .cerr;
    if (std.mem.eql(u8, symbol_name, "__ZNSt3__14clogE")) return .clog;
    return null;
}

pub fn isBridgedLibcppDataSymbol(symbol_name: []const u8) bool {
    if (!isAbiDataSymbol(symbol_name)) return false;
    // Rosette owns the runtime for every stream class the bridge models:
    // constructors, base inits, methods, manipulators and destructors are
    // all intercepted, and the bridge installs its own synthetic vtables
    // (`cxx_object_model.ensureType`) instead of reading dyld-bound ones.
    // Routing their vtable/VTT/typeinfo bindings through the deferred
    // materializer instead would hand the guest zeroed synthetic records
    // (or, for the ostringstream family, a VTT whose slots are all zero)
    // that the *bridge's* object model then has to fight. The ostringstream
    // complete-object destructor in particular loads its hidden VTT before
    // entering D2, so its `__ZTT` data must follow the bridge, not dyld.
    const families = [_][]const u8{
        "basic_ifstream",
        "basic_istream",
        "basic_ostream",
        "basic_ostringstream",
        "basic_istringstream",
        "basic_stringstream",
        "basic_stringbuf",
        "basic_streambuf",
        "basic_filebuf",
        "basic_ios",
        "ios_base",
    };
    for (families) |family| {
        if (std.mem.indexOf(u8, symbol_name, family) != null) return true;
    }
    return false;
}

pub fn bindingRequiresBoundThunk(section: macho_metadata.Section, is_runtime_callback: bool) bool {
    return is_runtime_callback or std.mem.eql(u8, section.name, "__got");
}

pub fn registerNativeWindowHandles(self: anytype) void {
    return native_window.registerNativeWindowHandles(self);
}

pub fn ensureNativeApplication(self: anytype) bool {
    return native_window.ensureNativeApplication(self);
}

pub fn ensureNativeWindow(self: anytype) bool {
    return native_window.ensureNativeWindow(self);
}

pub fn setNativeWindowTitle(self: anytype, title: []const u8) bool {
    return native_window.setNativeWindowTitle(self, title);
}

pub fn setNativeWindowSize(self: anytype, width: i32, height: i32) bool {
    return native_window.setNativeWindowSize(self, width, height);
}

pub fn showNativeWindow(self: anytype) bool {
    return native_window.showNativeWindow(self);
}

pub fn hideNativeWindow(self: anytype) bool {
    return native_window.hideNativeWindow(self);
}

pub fn setNativeWindowFullscreen(self: anytype, fullscreen: bool) bool {
    return native_window.setNativeWindowFullscreen(self, fullscreen);
}

pub fn nativeViewToken(self: anytype) u64 {
    return native_window.nativeViewToken(self);
}

pub fn nativeWindowToken(self: anytype) u64 {
    return native_window.nativeWindowToken(self);
}

pub fn nativeWindowWidth(self: anytype) u32 {
    return native_window.nativeWindowWidth(self);
}

pub fn nativeWindowHeight(self: anytype) u32 {
    return native_window.nativeWindowHeight(self);
}

pub fn validateNativeMetalLayerToken(self: anytype, token: u64) bool {
    return native_window.validateNativeMetalLayerToken(self, token);
}

pub fn nativeMetalLayerHostPointer(self: anytype) usize {
    return native_window.nativeMetalLayerHostPointer(self);
}

pub fn prepareNativeMetalDrawable(self: anytype, width: u32, height: u32) bool {
    return native_window.prepareNativeMetalDrawable(self, width, height);
}

pub fn setNativeMetalDrawableOwner(self: anytype, owned_by_swapchain: bool) bool {
    return native_window.setNativeMetalDrawableOwner(self, owned_by_swapchain);
}

pub fn noteNativeVulkanSurfaceBound(self: anytype, layer_token: u64, guest_surface: u64, host_surface: u64) void {
    return native_window.noteNativeVulkanSurfaceBound(self, layer_token, guest_surface, host_surface);
}

pub fn presentNativeDiagnosticFrame(
    self: anytype,
    serial: u64,
    width: u32,
    height: u32,
    stage: u32,
) bool {
    return native_window.presentNativeDiagnosticFrame(self, serial, width, height, stage);
}

pub fn pumpNativeWindowEvents(self: anytype) void {
    return native_window.pumpNativeWindowEvents(self);
}

pub fn legacyTracepointRole(boundary: gpu.bringup_gate.Boundary) execution_tracepoints.Role {
    return switch (boundary) {
        .guest_swap_requested, .swap_notified_to_graphics_system => .swap,
        .issue_swap => .command_swap,
        .xe_swap_decoded => .xe_swap_decode,
        .initialize_ring_buffer, .enable_rptr_write_back => .ring_setup,
        .execute_primary_buffer => .command_processor,
        .refresh_guest_output, .refresh_guest_output_impl => .presenter,
        else => .other,
    };
}

pub fn boundaryLabel(index: u8) []const u8 {
    if (index == execution_tracepoints.unbound_boundary) return "<none>";
    if (index >= gpu.bringup_gate.boundary_count) return "<invalid>";
    const boundary: gpu.bringup_gate.Boundary = @enumFromInt(index);
    return boundary.label();
}
