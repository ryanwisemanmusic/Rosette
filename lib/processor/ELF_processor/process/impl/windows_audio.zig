const process = @import("../../process.zig");
const ElfState = process.ElfState;
const __ProcessInternals = process.__ProcessInternals;
const __StateInternals = ElfState.__StateInternals;
const process_impl_execution = @import("execution.zig");
const process_impl_guest_diagnostics = @import("guest_diagnostics.zig");
const process_impl_kernel_services = @import("kernel_services.zig");
const __process_AUDIO_STAGE_COUNT = __ProcessInternals._AUDIO_STAGE_COUNT;
const __process_ChainStage = __ProcessInternals._ChainStage;
const __process_log = __ProcessInternals._log;
const __process_std = __ProcessInternals._std;

pub fn openWindowsHostAudio(self: *ElfState, sample_rate: u32, channels: u32, bits_per_sample: u32, is_float: bool) bool {
    const hooks = self.windows_audio_hooks;
    const open = hooks.open orelse return false;
    self.windows_audio_host_open_attempts +|= 1;
    const opened = open(hooks.context, sample_rate, channels, bits_per_sample, @intFromBool(is_float)) != 0;
    if (!opened) {
        self.windows_audio_host_open_failures +|= 1;
        __process_log.info("PE64 Windows audio: host device refused format rate={d} channels={d} bits={d} float={}; the guest keeps its clocked null sink", .{
            sample_rate,
            channels,
            bits_per_sample,
            is_float,
        });
        return false;
    }
    self.windows_audio_host_connected = true;
    __process_log.info("PE64 Windows audio: host device opened rate={d} channels={d} bits={d} float={}; guest frames are now audible", .{
        sample_rate,
        channels,
        bits_per_sample,
        is_float,
    });
    return true;
}

pub fn submitWindowsHostAudio(self: *ElfState, data: u64, length: u32) void {
    if (!self.windows_audio_host_connected or length == 0) return;
    const hooks = self.windows_audio_hooks;
    const submit = hooks.submit orelse return;
    const snapshot = self.allocator.alloc(u8, @intCast(length)) catch {
        self.windows_audio_host_bytes_dropped +|= length;
        return;
    };
    defer self.allocator.free(snapshot);
    if (!process_impl_execution.copyFromGuest(self, snapshot, data)) return;
    // The host callback may enqueue or inspect the buffer while another
    // guest executor updates the original wave memory. Keep that borrow
    // inside Rosette-owned storage for the callback's full duration.
    const accepted = submit(hooks.context, snapshot.ptr, length);
    self.windows_audio_host_bytes_accepted +|= accepted;
    self.windows_audio_host_bytes_dropped +|= (length -| accepted);
}

pub fn closeWindowsHostAudio(self: *ElfState) void {
    if (!self.windows_audio_host_connected) return;
    const hooks = self.windows_audio_hooks;
    if (hooks.close) |close| close(hooks.context);
    self.windows_audio_host_connected = false;
}

pub fn windowsAudioSinkLabel(self: *const ElfState) []const u8 {
    if (!self.windows_audio_host_connected) return "clocked_null_sink";
    const hooks = self.windows_audio_hooks;
    const served = if (hooks.callbacks_served) |callbacks| callbacks(hooks.context) else 0;
    return if (served != 0) "host_device" else "opened_but_silent";
}

pub fn audioChainStages(self: *const ElfState) [__process_AUDIO_STAGE_COUNT]__process_ChainStage {
    const hooks = self.windows_audio_hooks;
    var host_played: u64 = 0;
    var host_dropped: u64 = 0;
    var host_underruns: u64 = 0;
    if (hooks.transfer_counters) |counters| {
        counters(hooks.context, &host_played, &host_dropped, &host_underruns);
    }
    const served = if (hooks.callbacks_served) |callbacks| callbacks(hooks.context) else 0;
    const m = struct {
        const setup = "_ZN2xe3apu11AudioSystem5SetupEPNS_6kernel11KernelStateE";
        const register = "_ZN2xe3apu11AudioSystem14RegisterClientEjjPy";
        const driver = "_ZN2xe3apu3sdl14SDLAudioDriver10InitializeEv";
        const submit = "_ZN2xe3apu11AudioSystem11SubmitFrameEyPf";
    };

    return [__process_AUDIO_STAGE_COUNT]__process_ChainStage{
        .{
            .name = "apu_backend_created",
            .owner = "xenia:emulator",
            .met = process_impl_kernel_services.guestMilestoneHitsNamed(self, m.setup) != 0,
            .evidence = "AudioSystem_Setup_entries",
            .value = process_impl_kernel_services.guestMilestoneHitsNamed(self, m.setup),
            .observable = process_impl_kernel_services.guestMilestoneArmed(self, m.setup),
        },
        .{
            // Xenia touches no host audio API until the guest asks for a
            // port: the driver is created from RegisterClient, and
            // SDL_InitSubSystem lives inside the driver. A run with no
            // WinMM traffic and nothing here is a title that has not
            // asked for sound, not a backend Rosette failed to provide -
            // and the old chain blamed the apu factory for it.
            .name = "title_registered_audio_client",
            .owner = "guest-title",
            .met = process_impl_kernel_services.guestMilestoneHitsNamed(self, m.register) != 0 or
                self.guest_kernel_calls.witnessHitsFor(m.register) != 0,
            .evidence = "RegisterClient_entries",
            .value = process_impl_kernel_services.guestMilestoneHitsNamed(self, m.register),
            .observable = process_impl_kernel_services.guestMilestoneArmed(self, m.register),
            .witness = process_impl_guest_diagnostics.witnessLabel(m.register),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.register),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.register),
            .when_unmet = "the title has not asked the kernel for an audio port. Xenia creates no driver and calls no host audio API until it does, so nothing here is Rosette's yet",
        },
        .{
            .name = "sdl_driver_initialized",
            .owner = "xenia:audio-driver",
            .met = process_impl_kernel_services.guestMilestoneHitsNamed(self, m.driver) != 0,
            .evidence = "SDLAudioDriver_Initialize_entries",
            .value = process_impl_kernel_services.guestMilestoneHitsNamed(self, m.driver),
            .observable = process_impl_kernel_services.guestMilestoneArmed(self, m.driver),
        },
        .{
            .name = "backend_reached_rosette",
            .owner = "xenia:apu-factory",
            .met = self.windows_audio_import_calls != 0,
            .evidence = "winmm_import_calls",
            .value = self.windows_audio_import_calls,
        },
        .{
            .name = "guest_wave_device_open",
            .owner = "xenia:audio-driver",
            .met = self.windows_audio_open_successes != 0,
            .evidence = "wave_opens",
            .value = self.windows_audio_open_successes,
        },
        .{
            .name = "host_device_open",
            .owner = "rosette:coreaudio",
            .met = self.windows_audio_host_connected,
            .evidence = "host_open_attempts",
            .value = self.windows_audio_host_open_attempts,
        },
        .{
            .name = "title_submitted_pcm",
            .owner = "guest-title",
            .met = process_impl_kernel_services.guestMilestoneHitsNamed(self, m.submit) != 0 or
                self.guest_kernel_calls.witnessHitsFor(m.submit) != 0,
            .evidence = "SubmitFrame_entries",
            .value = process_impl_kernel_services.guestMilestoneHitsNamed(self, m.submit),
            .observable = process_impl_kernel_services.guestMilestoneArmed(self, m.submit),
            .witness = process_impl_guest_diagnostics.witnessLabel(m.submit),
            .witness_value = self.guest_kernel_calls.witnessHitsFor(m.submit),
            .witness_armed = self.guest_kernel_calls.witnessArmedFor(m.submit),
            .when_unmet = "the title has produced no PCM. Frames can still be silent once it does, but nothing before this point can be",
        },
        .{
            .name = "guest_wrote_frames",
            .owner = "xenia:audio-worker",
            .met = self.windows_audio_write_calls != 0,
            .evidence = "wave_writes",
            .value = self.windows_audio_write_calls,
        },
        .{
            .name = "frames_carry_signal",
            .owner = "guest-title",
            .met = self.windows_audio_nonzero_buffers != 0,
            .evidence = "nonzero_buffers",
            .value = self.windows_audio_nonzero_buffers,
        },
        .{
            .name = "host_device_asked_for_audio",
            .owner = "rosette:coreaudio",
            .met = served != 0,
            .evidence = "device_callbacks",
            .value = served,
        },
        .{
            .name = "device_bytes_delivered",
            .owner = "rosette:coreaudio",
            .met = host_played != 0,
            .evidence = "device_played_bytes",
            .value = host_played,
        },
    };
}

pub fn audioChainWall(self: *const ElfState) ?__process_ChainStage {
    for (audioChainStages(self)) |stage| {
        if (!stage.observable) continue;
        if (!stage.met) return stage;
    }
    return null;
}

pub fn reportAudioChain(self: *const ElfState) void {
    const hooks = self.windows_audio_hooks;
    var host_played: u64 = 0;
    var host_dropped: u64 = 0;
    var host_underruns: u64 = 0;
    if (hooks.transfer_counters) |counters| {
        counters(hooks.context, &host_played, &host_dropped, &host_underruns);
    }
    const stages = audioChainStages(self);
    var met_count: usize = 0;
    var observable_count: usize = 0;
    var first_unmet: ?usize = null;
    for (stages, 0..) |stage, index| {
        if (!stage.observable) continue;
        observable_count += 1;
        if (stage.met) {
            met_count += 1;
        } else if (first_unmet == null) {
            first_unmet = index;
        }
    }

    __process_log.info("PE64 AUDIO CHAIN: {d}/{d} observable stages met ({d} not observable in this image); sink={s}", .{
        met_count,
        observable_count,
        stages.len - observable_count,
        windowsAudioSinkLabel(self),
    });
    const audio_policy = if (self.windows_audio_environment_queries == 0)
        "not_queried"
    else if (self.windows_audio_environment_driver.len != 0)
        self.windows_audio_environment_driver
    else
        "unset_or_unrecognized";
    __process_log.info("PE64 AUDIO CHAIN: completions waveOutWrite={d} WOM_DONE_callbacks={d} callback_failures={d} nonzero_buffers={d} pacing_waits={d} ({d} requested writer-park ms, NOT host-blocked ms); cooperative pacing leaves other workers runnable. A CALLBACK_FUNCTION client needs WOM_DONE before writing again", .{
        self.windows_audio_write_calls,
        self.windows_audio_callback_dispatches,
        self.windows_audio_callback_failures,
        self.windows_audio_nonzero_buffers,
        self.windows_audio_pacing_waits,
        self.windows_audio_pacing_wait_ms,
    });
    // The milestone count can read zero when the build inlined
    // WriteRegister into its MMIO thunk; the fault census cannot, because
    // Rosette raises the fault that delivers every register write.
    const xma_writes = @max(process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3apu10XmaDecoder13WriteRegisterEjj"), self.xma_registers.faults);
    const xma_work = process_impl_kernel_services.guestMilestoneHitsNamed(self, "_ZN2xe3apu10XmaContext4WorkEv");
    const xma_kicks = self.xma_registers.kicks;
    const title_signal_verdict: []const u8 = if (self.audio_title_frames_checked == 0)
        "no frame the title submitted was readable, so the title's side of the signal is unmeasured"
    else if (self.audio_title_frames_nonzero == 0 and xma_writes == 0)
        "all sampled readable title frames are silence and no XMA decoder register entry was observed; nonsilent title audio has not been proven, not a lost host-device signal"
    else if (self.audio_title_frames_nonzero == 0 and xma_kicks == 0)
        "all sampled readable title frames are silence and the title has touched XMA registers without kicking a context (PE64 XMA REGISTERS): it has given the decoder nothing to decode, so its mixer has only silence to submit and this stage moves when the title starts a sound"
    else if (self.audio_title_frames_nonzero == 0 and xma_work == 0)
        "the title kicked XMA contexts and no XMA context ever did work, so its compressed audio is not being decoded and its frames are silence"
    else if (self.audio_title_frames_nonzero == 0)
        "XMA contexts decode, and all sampled readable title frames are still silence"
    else if (self.windows_audio_nonzero_buffers == 0)
        "the title submits audible frames and every buffer written to WinMM is silence: the signal is lost between Xenia's SDL driver and waveOutWrite"
    else
        "the title's frames carry signal and so do the buffers written to the device";
    __process_log.info("PE64 AUDIO CHAIN: title signal frames_checked={d} nonzero={d} first_nonzero_step={d} xma_register_writes={d} xma_context_work={d}; {s}", .{
        self.audio_title_frames_checked,
        self.audio_title_frames_nonzero,
        self.audio_title_first_nonzero_step,
        xma_writes,
        xma_work,
        title_signal_verdict,
    });
    __process_log.info("PE64 AUDIO POLICY: SDL_AUDIODRIVER guest_queries={d} selected={s}", .{
        self.windows_audio_environment_queries,
        audio_policy,
    });
    process_impl_guest_diagnostics.reportXmaRegisters(self);
    for (stages, 0..) |stage, index| {
        const marker: []const u8 = if (!stage.observable)
            "unobservable (this image does not name the symbol)"
        else if (stage.met)
            "met"
        else if (first_unmet != null and index == first_unmet.?)
            "UNMET <- the wall"
        else
            "unmet (downstream of the wall)";
        __process_log.info("PE64 AUDIO CHAIN:   {s:<28} owner={s:<22} {s} ({s}={d})", .{
            stage.name,
            stage.owner,
            marker,
            stage.evidence,
            stage.value,
        });
        if (stage.witness.len != 0 and stage.witness_armed) {
            __process_log.info("PE64 AUDIO CHAIN:     witness {s}={d} (the guest-side export shim, which only the title can reach)", .{
                stage.witness,
                stage.witness_value,
            });
        }
        if (stage.observable and !stage.met and stage.when_unmet.len != 0) {
            __process_log.info("PE64 AUDIO CHAIN:     -> {s}", .{stage.when_unmet});
        }
    }
    if (host_dropped != 0 or host_underruns != 0) {
        __process_log.info("PE64 AUDIO CHAIN:   pacing: dropped_bytes={d} (guest ahead of the device) underruns={d} (guest behind it)", .{
            host_dropped,
            host_underruns,
        });
    }
    if (first_unmet) |index| {
        __process_log.info("PE64 AUDIO CHAIN:   verdict: '{s}' is the earliest unmet stage and it belongs to {s}", .{
            stages[index].name,
            stages[index].owner,
        });
        if (__process_std.mem.eql(u8, stages[index].name, "title_registered_audio_client")) {
            __process_log.info("PE64 AUDIO CHAIN:   the title has not asked for an audio port. Xenia creates no driver and calls no host audio API until it does, so there is nothing here for Rosette to have failed at; this stage moves when the title does", .{});
        }
        if (__process_std.mem.eql(u8, stages[index].name, "backend_reached_rosette")) {
            // Keep this branch as the single failure-point owner so a
            // startup snapshot cannot claim XAudio2 was used.
            if (self.windows_audio_environment_queries == 0) {
                __process_log.info("PE64 AUDIO CHAIN:   no WinMM boundary was observed and SDL_AUDIODRIVER was never queried; the audio worker did not reach SDL initialization in this observation window", .{});
            } else if (self.windows_audio_environment_driver.len != 0) {
                __process_log.info("PE64 AUDIO CHAIN:   SDL selected {s}, but no WinMM boundary was observed; the next finding is the SDL/WinMM dispatch boundary or an audio worker that stopped before device discovery", .{self.windows_audio_environment_driver});
            } else {
                __process_log.info("PE64 AUDIO CHAIN:   SDL_AUDIODRIVER was unset or unrecognized, so SDL used its compiled driver order; Rosetta did not claim a wave device", .{});
            }
        }
    } else {
        __process_log.info("PE64 AUDIO CHAIN:   verdict: guest frames reached a host device that consumed them", .{});
    }
}

pub fn logWindowsAudioStop(self: *const ElfState) void {
    const hooks = self.windows_audio_hooks;
    var host_played: u64 = 0;
    var host_dropped: u64 = 0;
    var host_underruns: u64 = 0;
    if (hooks.transfer_counters) |counters| {
        counters(hooks.context, &host_played, &host_dropped, &host_underruns);
    }
    const served = if (hooks.callbacks_served) |callbacks| callbacks(hooks.context) else 0;
    __process_log.info("PE64 Windows audio host: sink={s} device_open={} open={d}/{d} bytes_accepted={d} bytes_dropped={d} device_callbacks={d} device_played_bytes={d} device_underruns={d}; a zero callback count is the reading that proves the host never asked for audio", .{
        windowsAudioSinkLabel(self),
        self.windows_audio_host_connected,
        self.windows_audio_host_open_attempts -| self.windows_audio_host_open_failures,
        self.windows_audio_host_open_attempts,
        self.windows_audio_host_bytes_accepted,
        self.windows_audio_host_bytes_dropped,
        served,
        host_played,
        host_underruns,
    });
    __process_log.info("PE64 Windows audio: sink={s} host_output={s} imports={d} format_queries={d} open={d}/{d} format_rejections={d} prepare={d} unprepare={d} reset={d} write={d} close={d} buffers={d}/{d} callbacks={d} callback_failures={d} bytes={d} nonzero_buffers={d} last_data=0x{x} last_bytes={d} last_checksum=0x{x}", .{
        windowsAudioSinkLabel(self),
        if (self.windows_audio_host_connected) "connected" else "not_connected",
        self.windows_audio_import_calls,
        self.windows_audio_format_queries,
        self.windows_audio_open_successes,
        self.windows_audio_open_calls,
        self.windows_audio_format_rejections,
        self.windows_audio_prepare_calls,
        self.windows_audio_unprepare_calls,
        self.windows_audio_reset_calls,
        self.windows_audio_write_calls,
        self.windows_audio_close_calls,
        self.windows_audio_buffers_submitted,
        self.windows_audio_buffers_completed,
        self.windows_audio_callback_dispatches,
        self.windows_audio_callback_failures,
        self.windows_audio_bytes_submitted,
        self.windows_audio_nonzero_buffers,
        self.windows_audio_last_data,
        self.windows_audio_last_bytes,
        self.windows_audio_last_checksum,
    });
}
