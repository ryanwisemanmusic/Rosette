#!/usr/bin/env bash
# Rosette-owned launcher for the upstream Xenia Windows PE capsule.
#
# The Xenia checkout remains a source tree.  This adapter selects the isolated
# Rosette build bundle, supplies optional media, and invokes Rosette's PE64
# runner.  It deliberately does not patch or execute scripts from Xenia's
# source tree.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

help() {
    cat <<'EOF'
Rosette Xenia launcher

  rosette-guest-run.sh [options]

Options:
  --source-root PATH       Upstream Xenia checkout (default: XENIA_ROOT).
  --build-dir PATH         Isolated Rosette build directory.
  --bundle-dir PATH        Bundle containing xenia_canary.exe.
  --media-image PATH       Host ISO/media image to expose to the PE guest.
  --trace PATH             Rosette trace-log destination.
  --run-log PATH           Detailed run-log destination (default: latest log in the stable run folder).
  --max-steps N            Optional diagnostic bound; normal runs are unlimited.
  --build-if-missing       Build the Windows capsule when the bundle is absent.
  --rebuild                Rebuild the Windows capsule before launching.
  --parse-only             Parse and preflight the PE without executing it.
  --arg VALUE              Add one Windows command-line argument.
  --print                  Print the resolved launch and exit.
  --help                   Show this help.

Environment:
  ROSETTE_XENIA_APU (default: sdl; 'unset' leaves Xenia's own config alone),
  ROSETTE_PE64_SDL_AUDIO_DRIVER (default: winmm; 'unset', 'default', or 'any'
    restores SDL's compiled driver order),
  ROSETTE_XENIA_ROOT, ROSETTE_XENIA_WINDOWS_BUILD_DIR,
  ROSETTE_XENIA_WINDOWS_BUNDLE_DIR, ROSETTE_XENIA_MEDIA_IMAGE,
  ROSETTE_XENIA_MEDIA_SHA256 (optional exact media identity),
  ROSETTE_XENIA_SCENARIO (explicit label for comparable benchmark runs),
  ROSETTE_XENIA_LOG_LEVEL (default: 1; Xenia warning-level output),
  ROSETTE_XENIA_TRACE_LOG, ROSETTE_XENIA_RUN_LOG, ROSETTE_XENIA_ROSETTE_DIR,
  ROSETTE_XENIA_GUEST_CJK_FONT (default: 0; set 1 to map a host CJK font; the
    Japanese atlas is intentionally expensive and can delay the first frame),
  ROSETTE_XENIA_RUNNER, ROSETTE_ELF_GRAPHICS_PROGRESS_TRACE,
  ROSETTE_ELF_GRAPHICS_BOUNDARY_TRACE, ROSETTE_ELF_GRAPHICS_STATE_DUMP,
  ROSETTE_VULKAN_REPORT_VERBOSE (default: 0; 1 restores per-sample full reports),
  ROSETTE_VULKAN_REPORT_INTERVAL_MS (default: 5000; compact progress cadence),
  ROSETTE_FSI_EVIDENCE (default: 1; save bounded guest/native shader modules
    and all FSI pipeline identities beside run logs; 0 disables the archive),
  ROSETTE_VULKAN_GFXR (default: 1; GFXReconstruct is armed before Vulkan
    starts, then press F10 in game to record one frame beside the run log;
    set 0/off to disable, or use frames:N for fixed present frames),
  ROSETTE_ELF_TRACE_WINDOWS_MEMORY, ROSETTE_XENIA_FATAL_POINT_TERMINATE,
  ROSETTE_ELF_TRACE_WINDOWS_AUDIO,
  ROSETTE_PE64_NATIVE_PTHREAD_COND, ROSETTE_PE64_GUEST_WAIT_COMPAT,
  ROSETTE_PE64_GUEST_SCHEDULER, ROSETTE_PE64_GUEST_SCHEDULER_QUANTUM,
  ROSETTE_PE64_GUEST_SCHEDULER_SLICE, ROSETTE_PE64_GUEST_SCHEDULER_EXPLICIT_STRIDE,
  ROSETTE_PE64_XENIA_RIJNDAEL_ACCELERATOR, ROSETTE_PE64_XENIA_SHA1_ACCELERATOR,
  ROSETTE_PE64_XENIA_TABULATE_ACCELERATOR.

Picture frame 1 starts at first observed acquired-image RGB detail with an
accepted, completed native present. Raw Vulkan presents remain diagnostic
transport counters; UI clears never start the picture epoch.
EOF
}

source_root="${ROSETTE_XENIA_ROOT:-${XENIA_ROOT:-}}"
build_dir="${ROSETTE_XENIA_WINDOWS_BUILD_DIR:-${repo_root}/build/xenia-windows-clean}"
bundle_dir="${ROSETTE_XENIA_WINDOWS_BUNDLE_DIR:-${build_dir}/bundle}"
media_image="${ROSETTE_XENIA_MEDIA_IMAGE:-}"
media_origin="${ROSETTE_XENIA_MEDIA_IMAGE:+environment}"
xenia_log_level="${ROSETTE_XENIA_LOG_LEVEL:-1}"
trace_log="${ROSETTE_XENIA_TRACE_LOG:-}"
run_log="${ROSETTE_XENIA_RUN_LOG:-}"
max_steps=""
build_if_missing=0
rebuild=0
parse_only=0
print_only=0
runner_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-root)
            [[ $# -ge 2 ]] || die "--source-root requires a path"
            source_root="$2"
            shift 2
            ;;
        --build-dir)
            [[ $# -ge 2 ]] || die "--build-dir requires a path"
            build_dir="$2"
            shift 2
            ;;
        --bundle-dir)
            [[ $# -ge 2 ]] || die "--bundle-dir requires a path"
            bundle_dir="$2"
            shift 2
            ;;
        --media-image)
            [[ $# -ge 2 ]] || die "--media-image requires a path"
            media_image="$2"
            media_origin="command-line"
            shift 2
            ;;
        --trace)
            [[ $# -ge 2 ]] || die "--trace requires a path"
            trace_log="$2"
            shift 2
            ;;
        --run-log)
            [[ $# -ge 2 ]] || die "--run-log requires a path"
            run_log="$2"
            shift 2
            ;;
        --max-steps)
            [[ $# -ge 2 ]] || die "--max-steps requires a positive integer"
            max_steps="$2"
            shift 2
            ;;
        --build-if-missing) build_if_missing=1; shift ;;
        --rebuild) rebuild=1; shift ;;
        --parse-only) parse_only=1; shift ;;
        --arg)
            [[ $# -ge 2 ]] || die "--arg requires a Windows argument"
            runner_args+=(--arg "$2")
            shift 2
            ;;
        --print) print_only=1; shift ;;
        --help|-h) help; exit 0 ;;
        *) die "unknown argument: $1 (use --help)" ;;
    esac
done

[[ -d "$source_root" ]] || die "Xenia source root does not exist: $source_root"
[[ -f "$source_root/CMakeLists.txt" ]] || die "Xenia source root is not an upstream checkout: $source_root"
source_root="$(cd "$source_root" && pwd)"

# Keep Xenia source untouched while storing Rosetta's run logs, traces, and
# generated evidence in the established Xenia-side `.rosette` data directory.
rosette_dir="${ROSETTE_XENIA_ROSETTE_DIR:-${repo_root}/.rosette/xenia-runs}"
[[ ! -L "$rosette_dir" ]] || die "Xenia Rosette directory must be a real directory: $rosette_dir"
mkdir -p "$rosette_dir"

if [[ -z "$media_image" ]]; then
    shopt -s nullglob
    media_candidates=("$bundle_dir"/*.iso)
    # The isolated Windows bundle deliberately does not copy multi-gigabyte
    # title media.  Its recent.toml still names the Halo 3 title, but the
    # Windows path stored there (C:\\xenia\\...) is not a host path and must
    # not be passed to the PE runner.  Prefer Rosette's verified Halo 3 XISO
    # export when the bundle has no adjacent image; do not accidentally select
    # an unrelated ISO such as Halo CE from the user's Desktop or Documents.
    if [[ "${#media_candidates[@]}" == 0 ]]; then
        media_candidates=("$repo_root"/ISO_FILE/8CEB1ABA7AC20BDAF62EEA16699E0227*.iso)
    fi
    shopt -u nullglob
    if [[ "${#media_candidates[@]}" == 1 ]]; then
        media_image="${media_candidates[0]}"
        media_origin="repository-verified-halo3-xiso"
    elif [[ "${#media_candidates[@]}" -gt 1 ]]; then
        die "multiple candidate media images found; pass --media-image explicitly: ${media_candidates[*]}"
    fi
fi

exe_path="$bundle_dir/xenia_canary.exe"
controller_db_asset="$repo_root/tools/guest_runtime/assets/gamecontrollerdb.txt"
runner="${ROSETTE_XENIA_RUNNER:-${repo_root}/app/bundling/zig-out/bin/rosette_exe_runner}"
if [[ ! -x "$runner" && -x "${repo_root}/zig-out/bin/rosette_exe_runner" ]]; then
    runner="${repo_root}/zig-out/bin/rosette_exe_runner"
fi

if [[ "$rebuild" == 1 || ("$build_if_missing" == 1 && ! -f "$exe_path") ]]; then
    build_args=(
        --source-root "$source_root"
        --build-dir "$build_dir"
        --bundle-dir "$bundle_dir"
        --prepare --configure --build --bundle
    )
    [[ -z "$media_image" ]] || build_args+=(--media-image "$media_image")
    "${script_dir}/rosette-guest-windows.sh" "${build_args[@]}"
fi

[[ -f "$exe_path" ]] || die "Xenia bundle is missing: $exe_path (use --build-if-missing or --rebuild)"
[[ -x "$runner" ]] || die "Rosette EXE runner is missing: $runner (run 'make -f build/Makefile exe-runner-build')"
[[ -s "$controller_db_asset" ]] || die "Rosette SDL GameControllerDB asset is missing: $controller_db_asset"
if [[ -n "$media_image" ]]; then
    [[ -f "$media_image" ]] || die "media image does not exist: $media_image"
fi
if [[ -n "$max_steps" ]]; then
    [[ "$max_steps" =~ ^[1-9][0-9]*$ ]] || die "--max-steps must be a positive integer"
fi

if [[ "$print_only" == 1 ]]; then
    printf 'Rosette Xenia launch\n'
    printf 'source root: %s\n' "$source_root"
    printf 'bundle: %s\n' "$bundle_dir"
    printf 'executable: %s\n' "$exe_path"
    printf 'runner: %s\n' "$runner"
    printf 'media: %s\n' "${media_image:-<none>}"
    printf 'media resolution: %s\n' "${media_origin:-none}"
    printf 'trace: %s\n' "${trace_log:-<latest trace under $rosette_dir/current>}"
    printf 'run log: %s\n' "${run_log:-<latest log under $rosette_dir/current>}"
    printf 'max steps: %s\n' "${max_steps:-<unlimited>}"
    printf 'sdl audio driver: %s\n' "${ROSETTE_PE64_SDL_AUDIO_DRIVER:-winmm}"
    printf 'parse only: %s\n' "$parse_only"
    exit 0
fi

[[ -d "$rosette_dir" && ! -L "$rosette_dir" ]] || die "Xenia Rosette directory must be a real directory: $rosette_dir"

# SDL resolves this file relative to the Windows process working directory,
# which is the isolated bundle. Existing user mappings are preserved. A
# missing or empty file is never allowed to turn into a guest warning.
if [[ -e "$bundle_dir/gamecontrollerdb.txt" ]]; then
    [[ -f "$bundle_dir/gamecontrollerdb.txt" && ! -L "$bundle_dir/gamecontrollerdb.txt" ]] ||
        die "Xenia bundle controller database must be a regular file: $bundle_dir/gamecontrollerdb.txt"
    [[ -s "$bundle_dir/gamecontrollerdb.txt" ]] || die "Xenia bundle controller database is empty: $bundle_dir/gamecontrollerdb.txt"
    controller_db_source="existing-bundle"
else
    cp -p "$controller_db_asset" "$bundle_dir/gamecontrollerdb.txt"
    controller_db_source="rosette-asset"
fi

export ROSETTE_ASYNC_LOG="${ROSETTE_ASYNC_LOG:-1}"
# The acquired-image readback window and its PNG pairs are off by default.
# Each readback ends in vkQueueWaitIdle on the one host thread every guest
# thread shares, and on 2026-09-20 they cost 122 s of a 1288 s run (9.5%).
# Set either to 1 to bring back the independent Cocoa preview or the captures;
# the main window's title carries the frame count either way.
export ROSETTE_VULKAN_CAPTURE="${ROSETTE_VULKAN_CAPTURE:-0}"
# GFXReconstruct is armed before Vulkan creates its instance. It writes no
# capture until F10 is pressed, so ordinary runs do not produce a large dump.
# Set 0/off to disable it; the explicit value is recorded in the run manifest.
export ROSETTE_VULKAN_GFXR="${ROSETTE_VULKAN_GFXR:-1}"
# Shader bytes are saved once at creation, with a 256 MiB run ceiling. This
# supplies post-fault evidence without instrumenting live Metal shaders.
export ROSETTE_FSI_EVIDENCE="${ROSETTE_FSI_EVIDENCE:-1}"
export ROSETTE_VULKAN_COCOA_PREVIEW="${ROSETTE_VULKAN_COCOA_PREVIEW:-0}"
export ROSETTE_INPUT_HASH_STALL_SECONDS="${ROSETTE_INPUT_HASH_STALL_SECONDS:-0}"
export ROSETTE_ELF_TRACE_WINDOWS_WAITS="${ROSETTE_ELF_TRACE_WINDOWS_WAITS:-1}"
export ROSETTE_ELF_TRACE_WINDOWS_AUDIO="${ROSETTE_ELF_TRACE_WINDOWS_AUDIO:-1}"
export ROSETTE_ELF_TRACE_WINDOWS_MEMORY="${ROSETTE_ELF_TRACE_WINDOWS_MEMORY:-1}"
# SDL's Windows backend tries WASAPI and DirectSound before WinMM. Rosette's
# modeled and audible boundary is WinMM, so select it through the guest
# environment rather than changing Xenia or SDL. The value remains
# caller-overridable for backend-comparison diagnostics.
export ROSETTE_PE64_SDL_AUDIO_DRIVER="${ROSETTE_PE64_SDL_AUDIO_DRIVER:-winmm}"
# A fatal point is evidence of a broken execution contract. Keep the runner
# strict by default so decode-cache conflicts/stale bytes, refused resources,
# and other high-severity findings cannot be silently buried in a long run.
# Set =0 only for an explicitly requested record-only diagnostic pass.
export ROSETTE_XENIA_FATAL_POINT_TERMINATE="${ROSETTE_XENIA_FATAL_POINT_TERMINATE:-1}"
# These are bounded diagnostics for the PE/Vulkan bring-up path. Progress is
# sampled at the 50M-step cadence; successful Vulkan boundary tracing is
# opt-in, while failed boundaries remain visible through the bounded failure
# path. The final state dump is one compact call-ring/memory snapshot when the
# guest run ends.
export ROSETTE_ELF_GRAPHICS_PROGRESS_TRACE="${ROSETTE_ELF_GRAPHICS_PROGRESS_TRACE:-1}"
export ROSETTE_ELF_GRAPHICS_BOUNDARY_TRACE="${ROSETTE_ELF_GRAPHICS_BOUNDARY_TRACE:-0}"
export ROSETTE_ELF_GRAPHICS_STATE_DUMP="${ROSETTE_ELF_GRAPHICS_STATE_DUMP:-1}"
# Full inventories belong to real transitions/exit; changing sample IDs and
# counters use compact wall-clock reports. No guest work or errors are gated.
export ROSETTE_VULKAN_REPORT_VERBOSE="${ROSETTE_VULKAN_REPORT_VERBOSE:-0}"
export ROSETTE_VULKAN_REPORT_INTERVAL_MS="${ROSETTE_VULKAN_REPORT_INTERVAL_MS:-5000}"
# Xenia's PE bootstrap is hosted by one Rosetta interpreter.  Keep MinGW's
# condition code native so it owns its semaphore protocol, and park guest
# workers on real wait objects so the owner loop does not spin through the
# same compatibility yield millions of times.  The policy remains
# caller-overridable for synchronization diagnosis.
# The Rijndael accelerator is Rosetta-owned and removes the XEX decrypt wall
# before the first graphics worker can submit a command buffer.
export ROSETTE_PE64_NATIVE_PTHREAD_COND="${ROSETTE_PE64_NATIVE_PTHREAD_COND:-1}"
export ROSETTE_PE64_GUEST_WAIT_COMPAT="${ROSETTE_PE64_GUEST_WAIT_COMPAT:-0}"
# Keep Xenia's single-interpreter worker policy explicit in every launch. The
# owner quantum is the maximum main-thread interval before Rosette gives a
# runnable worker a bounded turn; the slice is the maximum worker turn. Both
# remain caller-overridable for scheduler diagnosis without changing Xenia.
export ROSETTE_PE64_GUEST_SCHEDULER="${ROSETTE_PE64_GUEST_SCHEDULER:-1}"
export ROSETTE_PE64_GUEST_SCHEDULER_QUANTUM="${ROSETTE_PE64_GUEST_SCHEDULER_QUANTUM:-1000000}"
export ROSETTE_PE64_GUEST_SCHEDULER_SLICE="${ROSETTE_PE64_GUEST_SCHEDULER_SLICE:-10000}"
export ROSETTE_PE64_GUEST_SCHEDULER_EXPLICIT_STRIDE="${ROSETTE_PE64_GUEST_SCHEDULER_EXPLICIT_STRIDE:-1000}"
export ROSETTE_PE64_XENIA_RIJNDAEL_ACCELERATOR="${ROSETTE_PE64_XENIA_RIJNDAEL_ACCELERATOR:-1}"
export ROSETTE_PE64_XENIA_SHA1_ACCELERATOR="${ROSETTE_PE64_XENIA_SHA1_ACCELERATOR:-1}"
# XLast is semantic title metadata. Its guest pugi DOM parse is mandatory;
# remove the legacy switch so a caller cannot accidentally request the old
# empty-document bypass.
unset ROSETTE_PE64_XENIA_XLAST_ACCELERATOR
export ROSETTE_PE64_XENIA_TABULATE_ACCELERATOR="${ROSETTE_PE64_XENIA_TABULATE_ACCELERATOR:-1}"
if [[ -n "$xenia_log_level" ]]; then
    [[ "$xenia_log_level" =~ ^[0-4]$ ]] || die "ROSETTE_XENIA_LOG_LEVEL must be empty or an integer from 0 to 4"
    # Xenia's info-level startup report constructs large tabulate tables before
    # checking whether they will be emitted. Warning level preserves Xenia
    # warnings/errors while avoiding that metadata formatting tax. Rosette's
    # own detailed diagnostics remain independent of this setting.
    runner_args+=(--arg "--log_level=${xenia_log_level}")
fi
# Audio backend selection is a Rosette launch decision, not a Xenia edit.
#
# With `apu = any`, Xenia's factory always picks XAudio2 on Windows: its
# IsAvailable() is an unconditional true and constructing the system never
# touches a device, so SDL is never reached. The driver then fails much later,
# inside XAudio2AudioDriver::Initialize, because XAudio2_8.dll is outside the
# Win32 surface Rosette models -- and a title gets no audio at all.
#
# The SDL backend is statically linked into the same PE and falls through
# WASAPI and DirectSound (both refused) to WinMM, which Rosette does serve and
# now forwards to a real CoreAudio output queue. Selecting it on the command
# line leaves the bundle's config file untouched and stays overridable.
export ROSETTE_XENIA_APU="${ROSETTE_XENIA_APU:-sdl}"
if [[ -n "$ROSETTE_XENIA_APU" && "$ROSETTE_XENIA_APU" != "unset" ]]; then
    runner_args+=(--arg "--apu=${ROSETTE_XENIA_APU}")
fi
if [[ -n "$max_steps" ]]; then
    export ROSETTE_PE64_MAX_STEPS="$max_steps"
else
    unset ROSETTE_PE64_MAX_STEPS
fi

if [[ "$parse_only" == 1 ]]; then
    runner_args+=(--parse-only)
fi
if [[ -n "$media_image" ]]; then
    runner_args+=(--media "$media_image")
fi

systems_tool="${script_dir}/rosette_guest_systems.py"
requested_run_log="$run_log"
config_preflight_output="not-run(parse-only)"
config_preflight_action="not-run"
config_preflight_sha256="-"
config_preflight_bytes="0"
config_preflight_backup_sha256="-"
config_preflight_reason="-"
if [[ "$parse_only" != 1 ]]; then
    config_preflight_output="$(python3 "$systems_tool" preflight-config --bundle "$bundle_dir")" ||
        die "could not validate the generated Xenia TOML config"
    IFS=$'\t' read -r config_preflight_action config_preflight_sha256 config_preflight_bytes \
        config_preflight_backup_sha256 config_preflight_reason <<< "$config_preflight_output"
    case "$config_preflight_action" in
        valid|missing|repaired) ;;
        *) die "unexpected Xenia TOML preflight result: $config_preflight_action" ;;
    esac
    if [[ "$config_preflight_action" == repaired ]]; then
        printf 'Rosetta Xenia config preflight: repaired invalid TOML bytes=%s original_sha256=%s backup_sha256=%s reason=%s\n' \
            "$config_preflight_bytes" "$config_preflight_sha256" "$config_preflight_backup_sha256" "$config_preflight_reason"
    fi
fi
prepare_args=(
    prepare
    --run-root "$rosette_dir"
    --run-slot current
    --repo-root "$repo_root"
    --source-root "$source_root"
    --bundle "$bundle_dir"
    --executable "$exe_path"
    --runner "$runner"
    --media "${media_image:-}"
    --scenario "${ROSETTE_XENIA_SCENARIO:-unspecified}"
    --supervisor-pid "$$"
)
for arg in "${runner_args[@]}"; do
    # Keep option-looking runner values (for example, --arg and --log_level=1)
    # attached to their argparse option instead of letting argparse treat them
    # as new manager options.
    prepare_args+=("--launch-arg=$arg")
done
[[ -z "$run_log" ]] || prepare_args+=(--run-log "$run_log")
[[ -z "$trace_log" ]] || prepare_args+=(--trace-log "$trace_log")
run_context="$(python3 "$systems_tool" "${prepare_args[@]}")" || die "could not create a Rosetta run manifest"
eval "$run_context"
# The occlusion mode Xenia will use: a --arg override beats the bundle config,
# and no setting at all means Xenia's own default ("fast"), stated as such.
xenia_occlusion_effective="$xenia_occlusion_query"
[[ "$xenia_occlusion_effective" != "<unset>" ]] || xenia_occlusion_effective="unset-xenia-default-fast"
xenia_readback_effective="$xenia_readback_resolve"
xenia_render_path_effective="$xenia_render_target_path_vulkan"
for runner_arg in "${runner_args[@]}"; do
    case "$runner_arg" in
        --occlusion_query=*) xenia_occlusion_effective="${runner_arg#--occlusion_query=}-command-line" ;;
        --readback_resolve=*) xenia_readback_effective="${runner_arg#--readback_resolve=}-command-line" ;;
        --render_target_path_vulkan=*) xenia_render_path_effective="${runner_arg#--render_target_path_vulkan=}-command-line" ;;
    esac
done
export ROSETTE_RUN_ID="$run_id"
export ROSETTE_RUN_DIR="$run_dir"
export ROSETTE_BUILD_IDENTITY_SHA256="$build_identity_sha256"
export ROSETTE_XENIA_RUN_LOG="$run_log"
export ROSETTE_XENIA_RUN_MANIFEST="$run_manifest"

printf 'Rosette Xenia launch: bundle=%s media=%s trace=%s async=%s\n' \
    "$bundle_dir" "${media_image:-<none>}" "$trace_log" "$ROSETTE_ASYNC_LOG"
printf 'Rosette Xenia media resolution: %s\n' "${media_origin:-none}"
printf 'Rosette Xenia detailed log: %s\n' "$run_log"

{
    printf '# Rosette Xenia detailed run log\n'
    printf '# run_id = %s\n' "$run_id"
    printf '# build_identity_sha256 = %s\n' "$build_identity_sha256"
    printf '# scenario = %s\n' "${ROSETTE_XENIA_SCENARIO:-unspecified}"
    printf '# started_utc = %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'source_root = %s\n' "$source_root"
    printf 'bundle = %s\n' "$bundle_dir"
    printf 'executable = %s\n' "$exe_path"
    printf 'runner = %s\n' "$runner"
    printf 'run_manifest = %s\n' "$run_manifest"
    printf 'xenia_config_preflight = action=%s bytes=%s original_sha256=%s backup_sha256=%s reason=%s\n' \
        "$config_preflight_action" "$config_preflight_bytes" "$config_preflight_sha256" \
        "$config_preflight_backup_sha256" "$config_preflight_reason"
    printf 'xenia_gpu_render_settings = render_target_path_vulkan=%s readback_resolve=%s occlusion_query=%s\n' \
        "$xenia_render_path_effective" "$xenia_readback_effective" "$xenia_occlusion_effective"
    printf 'media = %s\n' "${media_image:-<none>}"
    printf 'media_resolution = %s\n' "${media_origin:-none}"
    printf 'trace = %s\n' "$trace_log"
    printf 'max_steps = %s\n' "${max_steps:-unlimited}"
    printf 'async = %s\n' "$ROSETTE_ASYNC_LOG"
    printf 'input_hash_stall_seconds = %s\n' "$ROSETTE_INPUT_HASH_STALL_SECONDS"
    printf 'windows_wait_trace = %s\n' "$ROSETTE_ELF_TRACE_WINDOWS_WAITS"
    printf 'windows_audio_trace = %s\n' "$ROSETTE_ELF_TRACE_WINDOWS_AUDIO"
    printf 'sdl_audio_driver = %s\n' "$ROSETTE_PE64_SDL_AUDIO_DRIVER"
    printf 'graphics_progress_trace = %s\n' "$ROSETTE_ELF_GRAPHICS_PROGRESS_TRACE"
    printf 'graphics_boundary_trace = %s\n' "$ROSETTE_ELF_GRAPHICS_BOUNDARY_TRACE"
    printf 'graphics_state_dump = %s\n' "$ROSETTE_ELF_GRAPHICS_STATE_DUMP"
    printf 'graphics_report_verbose = %s\n' "$ROSETTE_VULKAN_REPORT_VERBOSE"
    printf 'graphics_report_interval_ms = %s\n' "$ROSETTE_VULKAN_REPORT_INTERVAL_MS"
    printf 'graphics_gfxreconstruct_capture = %s\n' "$ROSETTE_VULKAN_GFXR"
    printf 'graphics_fsi_shader_evidence = %s\n' "$ROSETTE_FSI_EVIDENCE"
    printf 'graphics_frame_numbering = first_observed_RGB_detail+native_acceptance+queue_completion; raw_presents_are_transport_only\n'
    if [[ -z "$media_image" ]]; then
        printf 'content_scope = no_media; UI/fill presents do not measure title boot or game FPS\n'
    else
        printf 'content_scope = media_requested; title execution/content still require runtime evidence\n'
    fi
    printf 'windows_memory_trace = %s\n' "$ROSETTE_ELF_TRACE_WINDOWS_MEMORY"
    printf 'fatal_point_terminate = %s\n' "$ROSETTE_XENIA_FATAL_POINT_TERMINATE"
    printf 'gamecontrollerdb = %s (%s)\n' "$bundle_dir/gamecontrollerdb.txt" "$controller_db_source"
    printf 'native_pthread_condition_policy = %s\n' "$ROSETTE_PE64_NATIVE_PTHREAD_COND"
    printf 'guest_wait_compatibility_policy = %s\n' "$ROSETTE_PE64_GUEST_WAIT_COMPAT"
    printf 'guest_scheduler_explicit_stride = %s\n' "$ROSETTE_PE64_GUEST_SCHEDULER_EXPLICIT_STRIDE"
    printf 'xenia_rijndael_accelerator = %s\n' "$ROSETTE_PE64_XENIA_RIJNDAEL_ACCELERATOR"
    printf 'xenia_sha1_accelerator = %s\n' "$ROSETTE_PE64_XENIA_SHA1_ACCELERATOR"
    printf 'xenia_xlast_xml_dom = mandatory_guest_parser\n'
    printf 'xenia_tabulate_accelerator = %s\n' "$ROSETTE_PE64_XENIA_TABULATE_ACCELERATOR"
    printf 'xenia_log_level = %s\n' "${xenia_log_level:-<unchanged>}"
    printf 'xenia_apu = %s\n' "${ROSETTE_XENIA_APU:-<unchanged>}"
    printf 'runner_argv ='
    printf ' %q' "$runner" "$exe_path" "$trace_log"
    if (( ${#runner_args[@]} > 0 )); then
        printf ' %q' "${runner_args[@]}"
    fi
    printf '\n\n# --- launcher and runtime output ---\n'
} > "$run_log"

# Preserve the normal interactive output while retaining every boot line,
# periodic execution sample, warning, unresolved import, and exit diagnostic
# in the Xenia-local log.  The runner's exit status is kept separate from
# tee's status so diagnostics do not change the launch result.
set +e
if (( ${#runner_args[@]} > 0 )); then
    "$runner" "$exe_path" "$trace_log" "${runner_args[@]}" 2>&1 | tee -a "$run_log"
else
    "$runner" "$exe_path" "$trace_log" 2>&1 | tee -a "$run_log"
fi
pipeline_status=("${PIPESTATUS[@]}")
set -e
runner_status="${pipeline_status[0]:-1}"
tee_status="${pipeline_status[1]:-1}"

{
    printf '\n# --- end launcher and runtime output ---\n'
    printf 'runner_exit_status = %s\n' "$runner_status"
    printf 'finished_utc = %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    if [[ -f "$trace_log" && "$trace_log" != "$run_log" ]]; then
        printf '\n# --- internal Rosette PE trace ---\n'
        cat "$trace_log"
    fi
} >> "$run_log"

if ! python3 "$systems_tool" finalize --manifest "$run_manifest" --log "$run_log" --exit-status "$runner_status"; then
    printf 'WARNING: Rosetta run evidence finalization failed for %s\n' "$run_id" >&2
fi

# Keep the historical lookup path as a convenience copy of the newest run.
# The stable run folder keeps only the latest log and manifest; the run ID in
# their contents remains unique even though the filesystem slot is reused.
if [[ -z "$requested_run_log" && "$run_log" != "$rosette_dir/rosette-xenia.log" ]]; then
    cp -p "$run_log" "$rosette_dir/rosette-xenia.log"
fi

if [[ "$runner_status" != 0 ]]; then
    exit "$runner_status"
fi
exit "$tee_status"
